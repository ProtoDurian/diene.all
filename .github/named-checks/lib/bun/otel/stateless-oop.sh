#!/usr/bin/env bash
set -euo pipefail

# src/ is stateless OOP + DI: every function, arrow and method body lives inside a
# class body; classes keep only readonly fields set in the constructor (injected
# collaborators; src/test-helper/ doubles may record calls), and modules bind no
# let/var or mutable collection (parsed with TypeScript).

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src | grep -E '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$' || true)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }
[[ -d node_modules/typescript ]] || bun install --frozen-lockfile --ignore-scripts >/dev/null 2>&1 || { echo "❌ cannot install the TypeScript parser" >&2 && exit 1; }

failed=0
for path in "${files[@]}"; do
  state=1
  if [[ ${path} == src/test-helper/* ]]; then state=0; fi
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | STATE="${state}" FILE="${path}" bun -e '
    const ts = require(`${process.cwd()}/node_modules/typescript`);
    const file = process.env.FILE;
    const sf = ts.createSourceFile(file, await Bun.stdin.text(), ts.ScriptTarget.Latest, true, /x$/.test(file) ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const S = ts.SyntaxKind;
    const say = (n, what) => console.log(`${sf.getLineAndCharacterOfPosition(n.getStart(sf)).line + 1}:${what}`);
    const has = (n, k) => !!n.modifiers?.some(m => m.kind === k);
    const nameOf = m => m.name ? m.name.getText(sf) : "(index)";
    const kind = n => ts.isArrowFunction(n) ? "arrow" : ts.isFunctionExpression(n) || (ts.isFunctionDeclaration(n) && n.body) ? "function"
      : ts.isMethodDeclaration(n) || ts.isGetAccessorDeclaration(n) || ts.isSetAccessorDeclaration(n) ? "method" : undefined;
    const strip = e => { while (e && (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isTypeAssertionExpression(e) || ts.isSatisfiesExpression(e))) e = e.expression; return e; };
    const isThis = e => { e = strip(e); return !!e && (e.kind === S.ThisKeyword || e.kind === S.SuperKeyword); };
    const rooted = e => { e = strip(e); while (e && (ts.isPropertyAccessExpression(e) || ts.isElementAccessExpression(e))) e = strip(e.expression); return isThis(e); };
    const COLLECTIONS = new Set(["Map", "Set", "WeakMap", "WeakSet"]);
    const collection = e => { e = strip(e); return !!e && ts.isNewExpression(e) && ts.isIdentifier(e.expression) && COLLECTIONS.has(e.expression.text); };
    const targets = e => {
      e = strip(e);
      if (ts.isObjectLiteralExpression(e)) return e.properties.flatMap(p => ts.isPropertyAssignment(p) ? targets(p.initializer) : ts.isSpreadAssignment(p) ? targets(p.expression) : []);
      if (ts.isArrayLiteralExpression(e)) return e.elements.flatMap(x => targets(ts.isSpreadElement(x) ? x.expression : x));
      if (ts.isBinaryExpression(e) && e.operatorToken.kind === S.EqualsToken) return targets(e.left);
      return [e];
    };
    const MUTATORS = /^(Object\.(assign|defineProperty|defineProperties|setPrototypeOf)|Reflect\.(set|defineProperty|deleteProperty|setPrototypeOf))$/;
    const writes = (n, ctor) => {
      if (process.env.STATE === "0") return;
      if (ts.isBinaryExpression(n) && n.operatorToken.kind >= S.FirstAssignment && n.operatorToken.kind <= S.LastAssignment) {
        const plainField = ctor && n.operatorToken.kind === S.EqualsToken && ts.isPropertyAccessExpression(strip(n.left)) && isThis(strip(n.left).expression);
        if (!plainField && targets(n.left).some(rooted)) say(n, "instance state written outside the constructor");
        if (n.operatorToken.kind === S.EqualsToken && isThis(n.right)) say(n, "this aliased to a binding");
      }
      if ((ts.isPrefixUnaryExpression(n) || ts.isPostfixUnaryExpression(n)) && (n.operator === S.PlusPlusToken || n.operator === S.MinusMinusToken) && rooted(n.operand)) say(n, "instance state written outside the constructor");
      if (ts.isDeleteExpression(n) && rooted(n.expression)) say(n, "instance state written outside the constructor");
      if ((ts.isForInStatement(n) || ts.isForOfStatement(n)) && !ts.isVariableDeclarationList(n.initializer) && targets(n.initializer).some(rooted)) say(n, "instance state written outside the constructor");
      if (!ctor && ts.isCallExpression(n) && MUTATORS.test(strip(n.expression).getText(sf)) && n.arguments[0] && rooted(n.arguments[0])) say(n, "instance state written outside the constructor");
      if (ts.isVariableDeclaration(n) && n.initializer && isThis(n.initializer)) say(n, "this aliased to a binding");
    };
    const moduleState = n => {
      if (!ts.isVariableStatement(n) || !(ts.isSourceFile(n.parent) || ts.isModuleBlock(n.parent)) || has(n, S.DeclareKeyword)) return;
      if (!(n.declarationList.flags & ts.NodeFlags.Const) && !(n.declarationList.flags & ts.NodeFlags.Using)) say(n, "module-level mutable binding (let/var)");
      if (n.declarationList.declarations.some(d => d.initializer && collection(d.initializer))) say(n, "mutable collection held in state");
    };
    const member = m => {
      if (process.env.STATE === "0") { ts.forEachChild(m, c => visit(c, true, false)); return; }
      if (ts.isPropertyDeclaration(m)) {
        if (has(m, S.AccessorKeyword)) say(m, `mutable field ${nameOf(m)} (auto-accessor)`);
        else if (!has(m, S.ReadonlyKeyword)) say(m, `mutable field ${nameOf(m)} (fields must be readonly)`);
        if (m.initializer && collection(m.initializer)) say(m, "mutable collection held in state");
      }
      if (ts.isIndexSignatureDeclaration(m) && !has(m, S.ReadonlyKeyword)) say(m, "mutable field (index) (fields must be readonly)");
      if (ts.isSetAccessorDeclaration(m)) say(m, `setter ${nameOf(m)} on a stateless class`);
      if (ts.isConstructorDeclaration(m)) {
        for (const p of m.parameters) {
          const property = p.modifiers?.some(x => [S.PublicKeyword, S.PrivateKeyword, S.ProtectedKeyword, S.OverrideKeyword].includes(x.kind));
          if (property && !has(p, S.ReadonlyKeyword)) say(p, `mutable parameter property ${p.name.getText(sf)} (must be readonly)`);
          visit(p, true, false);
        }
        if (m.body) for (const st of m.body.statements) visit(st, true, true);
        return;
      }
      ts.forEachChild(m, c => visit(c, true, false));
    };
    const visit = (n, cls, ctor) => {
      if (ts.isClassLike(n)) {
        n.members.forEach(member);
        ts.forEachChild(n, c => ts.isClassElement(c) ? undefined : visit(c, cls, false));
        return;
      }
      const k = kind(n);
      if (k && !cls) say(n, `free ${k} outside a class body`);
      writes(n, ctor);
      moduleState(n);
      const inner = ctor && !ts.isFunctionLike(n);
      ts.forEachChild(n, c => visit(c, cls, inner));
    };
    visit(sf, false, false);
  ')"
  if [[ -n ${report} ]]; then
    while IFS=: read -r line what; do echo "❌ ${path}:${line}: ${what}" >&2; done <<<"${report}"
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ stateless-oop: ${#files[@]} src/ modules hold functions only inside class bodies and keep no mutable state"
