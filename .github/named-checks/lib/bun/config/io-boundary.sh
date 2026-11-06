#!/usr/bin/env bash
set -euo pipefail

# Effects live only in src/adapters/: there the YAML parser, node:fs/promises,
# node:path and process are allowed. Everything else under src/ imports only
# literal relative paths, zod and the published Result and core-utils packages
# (src/test-helper/ may also name this package root), and names no effectful global.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }
[[ -d node_modules/typescript ]] || bun install --frozen-lockfile --ignore-scripts >/dev/null 2>&1 || { echo "❌ cannot install the TypeScript parser" >&2 && exit 1; }

failed=0
for path in "${files[@]}"; do
  if [[ ! ${path} =~ \.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$ ]]; then
    echo "❌ ${path}: not a TypeScript/JavaScript source" >&2
    failed=1
    continue
  fi
  allowed='^(\.{1,2}/|@atomicloud/diene\.(result|core-utils)$|zod$)'
  allow_global='^$'
  if [[ ${path} == src/test-helper/* ]]; then
    allowed='^(\.{1,2}/|@atomicloud/diene\.(result|core-utils|config)$|zod$)'
  fi
  if [[ ${path} == src/adapters/* ]]; then
    allowed='^(\.{1,2}/|@atomicloud/diene\.(result|core-utils)$|zod$|yaml$|node:fs/promises$|node:path$)'
    allow_global='^process$'
  fi
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | ALLOWED="${allowed}" ALLOW_GLOBAL="${allow_global}" FILE="${path}" bun -e '
    const ts = require(`${process.cwd()}/node_modules/typescript`);
    const { dirname, join } = require("node:path/posix");
    const file = process.env.FILE;
    const sf = ts.createSourceFile(file, await Bun.stdin.text(), ts.ScriptTarget.Latest, true, /x$/.test(file) ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const allowed = new RegExp(process.env.ALLOWED), allowGlobal = new RegExp(process.env.ALLOW_GLOBAL);
    const S = ts.SyntaxKind;
    const GLOBALS = new Set(["process", "Bun", "Deno", "globalThis", "global", "window", "self", "console", "Buffer", "fetch", "require", "module", "exports", "__dirname", "__filename", "setInterval", "setTimeout", "setImmediate", "queueMicrotask", "eval", "crypto", "Reflect", "performance", "navigator", "XMLHttpRequest", "WebSocket", "Date", "Function", "Math"]);
    const FORBIDDEN_KEYS = new Set(["constructor", "__proto__"]);
    const say = line => console.log(line);
    const importOf = spec => {
      if (!allowed.test(spec)) say(`import ${spec}`);
      const target = join(dirname(file), spec);
      if (/^\.{1,2}\//.test(spec) && !file.startsWith("src/adapters/") && file !== "src/index.ts" && (/^src\/adapters(\/|$)/.test(target) || /^src(\/index(\.[jt]s)?)?\/?$/.test(target))) say(`import ${spec} (the domain reaches into src/adapters/ or the root barrel)`);
    };
    const constant = e => {
      while (e && (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isTypeAssertionExpression(e) || ts.isSatisfiesExpression(e))) e = e.expression;
      if (!e) return undefined;
      if (ts.isStringLiteralLike(e) || ts.isNumericLiteral(e)) return e.text;
      if (ts.isBinaryExpression(e) && e.operatorToken.kind === S.PlusToken) {
        const a = constant(e.left), b = constant(e.right);
        return a === undefined || b === undefined ? undefined : a + b;
      }
      if (ts.isTemplateExpression(e)) {
        let text = e.head.text;
        for (const span of e.templateSpans) { const v = constant(span.expression); if (v === undefined) return undefined; text += v + span.literal.text; }
        return text;
      }
      return undefined;
    };
    const inType = n => {
      for (let p = n.parent; p; p = p.parent) {
        if (ts.isExpressionWithTypeArguments(p)) return !(p.parent.token === S.ExtendsKeyword && ts.isClassLike(p.parent.parent));
        if (ts.isTypeNode(p) || ts.isInterfaceDeclaration(p) || ts.isTypeAliasDeclaration(p)) return true;
      }
      return false;
    };
    const named = n => {
      const p = n.parent;
      if ((ts.isPropertyAccessExpression(p) || ts.isQualifiedName(p)) && (p.name ?? p.right) === n) return true;
      if ((ts.isImportSpecifier(p) || ts.isExportSpecifier(p) || ts.isBindingElement(p)) && p.propertyName === n) return true;
      if (ts.isLabeledStatement(p) || ts.isBreakOrContinueStatement(p)) return true;
      return p.name === n && !ts.isShorthandPropertyAssignment(p);
    };
    const binds = (b, name) => ts.isIdentifier(b) ? b.text === name : !!b.elements?.some(e => !ts.isOmittedExpression(e) && binds(e.name, name));
    const ambient = st => !!(st.flags & ts.NodeFlags.Ambient) || !!st.modifiers?.some(m => m.kind === S.DeclareKeyword);
    const hoisted = (root, name) => {
      let found = false;
      const walk = n => {
        if (found || ts.isFunctionLike(n) || ts.isClassLike(n) || ts.isModuleDeclaration(n)) return;
        if (ts.isVariableDeclarationList(n) && !(n.flags & ts.NodeFlags.BlockScoped) && !ambient(n.parent) && n.declarations.some(d => binds(d.name, name))) found = true;
        ts.forEachChild(n, walk);
      };
      ts.forEachChild(root, walk);
      return found;
    };
    const declares = (scope, name, from) => {
      if (ts.isFunctionLike(scope) && (from === scope.body || scope.parameters?.includes(from)) && (scope.parameters.some(p => binds(p.name, name)) || (scope.body && hoisted(scope.body, name)))) return true;
      if (ts.isSourceFile(scope) && hoisted(scope, name)) return true;
      if ((ts.isFunctionExpression(scope) || ts.isClassExpression(scope)) && scope.name?.text === name) return true;
      if (ts.isCatchClause(scope) && scope.variableDeclaration && binds(scope.variableDeclaration.name, name)) return true;
      if ((ts.isForStatement(scope) || ts.isForInStatement(scope) || ts.isForOfStatement(scope)) && scope.initializer && ts.isVariableDeclarationList(scope.initializer) && scope.initializer.declarations.some(d => binds(d.name, name))) return true;
      for (const st of scope.statements ?? []) {
        if (ambient(st)) continue;
        if (ts.isVariableStatement(st) && st.declarationList.declarations.some(d => binds(d.name, name))) return true;
        if ((ts.isFunctionDeclaration(st) || ts.isClassDeclaration(st) || ts.isEnumDeclaration(st) || ts.isModuleDeclaration(st)) && st.name?.text === name) return true;
        const c = ts.isImportDeclaration(st) ? st.importClause : undefined, nb = c?.namedBindings;
        if (c && (c.name?.text === name || (nb && (ts.isNamespaceImport(nb) ? nb.name.text === name : nb.elements.some(e => e.name.text === name))))) return true;
      }
      return false;
    };
    const local = n => { for (let c = n, p = n.parent; p; c = p, p = p.parent) if (declares(p, n.text, c)) return true; return false; };
    const keyOf = k => !k ? undefined : ts.isComputedPropertyName(k) ? constant(k.expression) : ts.isIdentifier(k) || ts.isStringLiteralLike(k) || ts.isNumericLiteral(k) ? k.text : undefined;
    const hasInstanceOfFunction = n => {
      const proto = n.parent, access = proto.parent, key = access && access.argumentExpression;
      return ts.isPropertyAccessExpression(proto) && proto.name.text === "prototype" && ts.isElementAccessExpression(access) && ts.isPropertyAccessExpression(key) && key.expression.getText() === "Symbol" && key.name.text === "hasInstance";
    };
    const visit = n => {
      if (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) { if (n.moduleSpecifier && ts.isStringLiteralLike(n.moduleSpecifier)) importOf(n.moduleSpecifier.text); }
      else if (ts.isImportEqualsDeclaration(n) && ts.isExternalModuleReference(n.moduleReference)) { const e = n.moduleReference.expression; if (ts.isStringLiteralLike(e)) importOf(e.text); else say("non-literal require()"); }
      else if (ts.isCallExpression(n) && (n.expression.kind === S.ImportKeyword || (ts.isIdentifier(n.expression) && n.expression.text === "require"))) {
        const kind = n.expression.kind === S.ImportKeyword ? "import" : "require";
        const arg = n.arguments[0];
        if (arg && ts.isStringLiteralLike(arg)) importOf(arg.text); else say(`non-literal ${kind}()`);
      }
      else if (ts.isMetaProperty(n) && n.keywordToken === S.ImportKeyword) say("global import.meta");
      else if (ts.isPropertyAccessExpression(n) && n.name.text === "constructor") say("global .constructor");
      else if ((ts.isBindingElement(n) || ts.isPropertyAssignment(n) || ts.isShorthandPropertyAssignment(n)) && FORBIDDEN_KEYS.has(keyOf(n.propertyName ?? n.name))) say("global constructor (by string key)");
      else if (ts.isIdentifier(n) && GLOBALS.has(n.text) && !named(n) && !inType(n) && !local(n)) {
        let top = n;
        while (ts.isParenthesizedExpression(top.parent)) top = top.parent;
        const p = top.parent;
        if (n.text === "Date") { if (!(ts.isBinaryExpression(p) && p.operatorToken.kind === S.InstanceOfKeyword && p.right === top)) say("global Date"); }
        else if (n.text === "Function") { if (!hasInstanceOfFunction(n)) say("global Function"); }
        else if (n.text === "Math") { if (!(ts.isPropertyAccessExpression(p) && p.expression === n)) say("global Math"); else if (p.name.text === "random") say("global Math.random"); }
        else if (!allowGlobal.test(n.text)) say(`global ${n.text}`);
      }
      if ((ts.isStringLiteralLike(n) || ts.isBinaryExpression(n) || ts.isTemplateExpression(n)) && FORBIDDEN_KEYS.has(constant(n)) && !ts.isImportDeclaration(n.parent) && !inType(n)) say("global constructor (by string key)");
      ts.forEachChild(n, visit);
    };
    visit(sf);
  ')"
  if [[ -n ${report} ]]; then
    while read -r line; do echo "❌ ${path}: ${line}" >&2; done <<<"$(sort -u <<<"${report}")"
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  exit 1
fi

echo "✅ io-boundary: ${#files[@]} src/ modules keep effects in src/adapters/ (yaml, node:fs/promises, node:path, process); the rest import only relative paths, zod, result and core-utils"
