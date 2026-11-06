#!/usr/bin/env bash
set -euo pipefail

# Effects live only in src/adapters/: there pino, node:fs, every @opentelemetry/* package and
# process are allowed. Elsewhere src/ imports only literal relative paths, zod, the
# published Result, interfaces and core-utils packages, @opentelemetry/api,
# semantic-conventions, resources (no detectors) and the samplers of sdk-trace-base,
# and names no effectful global. src/test-helper/ may also name this package root and
# @atomicloud/diene.interfaces/test-helper, which no module republishes, directly or through an alias.

cd "$(git rev-parse --show-toplevel)"
# index tree == HEAD in CI; keeps local staged mutations visible
tree="$(git write-tree)"
mapfile -t files < <(git ls-tree -r --name-only "${tree}" -- src)
[[ ${#files[@]} -gt 0 ]] || { echo "❌ no sources under src/" >&2 && exit 1; }
[[ -d node_modules/typescript ]] || bun install --frozen-lockfile --ignore-scripts >/dev/null 2>&1 || { echo "❌ cannot install the TypeScript parser" >&2 && exit 1; }

pure='\.{1,2}/|@atomicloud/diene\.(result|interfaces|core-utils)$|zod$|@opentelemetry/(api|semantic-conventions|resources|sdk-trace-base)$'
failed=0
for path in "${files[@]}"; do
  if [[ ! ${path} =~ \.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$ ]]; then
    echo "❌ ${path}: not a TypeScript/JavaScript source" >&2
    failed=1
    continue
  fi
  allowed="^(${pure})"
  allow_global='^$'
  restrict=1
  types_only='^$'
  if [[ ${path} == src/test-helper/* ]]; then
    allowed="^(${pure}|@atomicloud/diene\.otel$|@atomicloud/diene\.interfaces/test-helper$)"
  fi
  if [[ ${path} == src/adapters/* ]]; then
    allowed='^(\.{1,2}/|@atomicloud/diene\.(result|interfaces|core-utils)$|zod$|pino$|node:fs$|@opentelemetry/[a-z0-9-]+$)'
    allow_global='^process$'
    restrict=0
    types_only='^node:https$'
  fi
  # shellcheck disable=SC2016
  report="$(git show "${tree}:${path}" | ALLOWED="${allowed}" ALLOW_GLOBAL="${allow_global}" TYPES_ONLY="${types_only}" RESTRICT="${restrict}" FILE="${path}" bun -e '
    const ts = require(`${process.cwd()}/node_modules/typescript`);
    const { dirname, join } = require("node:path/posix");
    const file = process.env.FILE;
    const sf = ts.createSourceFile(file, await Bun.stdin.text(), ts.ScriptTarget.Latest, true, /x$/.test(file) ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const allowed = new RegExp(process.env.ALLOWED), allowGlobal = new RegExp(process.env.ALLOW_GLOBAL);
    const S = ts.SyntaxKind;
    const GLOBALS = new Set(["process", "Bun", "Deno", "globalThis", "global", "window", "self", "console", "Buffer", "fetch", "require", "module", "exports", "__dirname", "__filename", "setInterval", "setTimeout", "setImmediate", "clearInterval", "clearTimeout", "clearImmediate", "queueMicrotask", "eval", "crypto", "Reflect", "performance", "navigator", "XMLHttpRequest", "WebSocket", "Date", "Function", "Math"]);
    const FORBIDDEN_KEYS = new Set(["constructor", "__proto__"]);
    const NAMES = process.env.RESTRICT === "1" ? { "@opentelemetry/sdk-trace-base": ["samplers", n => /^(\w*Sampler|Sampling\w*)$/.test(n)], "@opentelemetry/resources": ["non-detector names", n => !/detect/i.test(n)] } : {};
    const SHARED = "@atomicloud/diene.interfaces/test-helper";
    const say = line => console.log(line);
    const typeOnly = n => ts.isImportDeclaration(n) ? !!n.importClause && (n.importClause.isTypeOnly || (!n.importClause.name && !!n.importClause.namedBindings && ts.isNamedImports(n.importClause.namedBindings) && n.importClause.namedBindings.elements.every(e => e.isTypeOnly)))
      : ts.isExportDeclaration(n) && (n.isTypeOnly || (!!n.exportClause && ts.isNamedExports(n.exportClause) && n.exportClause.elements.every(e => e.isTypeOnly)));
    const namesOf = n => {
      if (ts.isImportDeclaration(n)) { const c = n.importClause, nb = c?.namedBindings; return !c || c.name || (nb && ts.isNamespaceImport(nb)) ? undefined : (nb?.elements ?? []).map(e => (e.propertyName ?? e.name).text); }
      if (ts.isExportDeclaration(n)) return n.exportClause && ts.isNamedExports(n.exportClause) ? n.exportClause.elements.map(e => (e.propertyName ?? e.name).text) : undefined;
      return undefined;
    };
    const importOf = (spec, n) => {
      if (!allowed.test(spec) && !(new RegExp(process.env.TYPES_ONLY).test(spec) && ts.isImportDeclaration(n) && !!n.importClause?.isTypeOnly)) say(`import ${spec}`);
      const target = join(dirname(file), spec), relative = /^\.{1,2}\//.test(spec);
      if (relative && !file.startsWith("src/adapters/") && file !== "src/index.ts" && (/^src\/adapters(\/|$)/.test(target) || /^src(\/index(\.[jt]s)?)?\/?$/.test(target))) say(`import ${spec} (the domain reaches into src/adapters/ or the root barrel)`);
      if (relative && file.startsWith("src/test-helper/") && !target.startsWith("src/test-helper/") && !typeOnly(n)) say(`import ${spec} (the TestHelper reaches the package only through @atomicloud/diene.otel)`);
      const rule = NAMES[spec];
      if (rule) { const names = namesOf(n); if (!names) say(`import ${spec} (only its ${rule[0]} may be named here)`); else for (const name of names.filter(x => !rule[1](x))) say(`import ${spec} { ${name} } (only its ${rule[0]} may be named here)`); }
      if (spec === SHARED && ts.isExportDeclaration(n)) say(`republishes ${SHARED}`);
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
      if (ts.isFunctionLike(scope) && (from === scope.body || scope.parameters?.includes(from)) && (scope.parameters.some(p => binds(p.name, name)) || (from === scope.body && hoisted(scope.body, name)))) return true;
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
    const shared = new Set();
    for (const st of sf.statements) {
      if (ts.isImportEqualsDeclaration(st) && ts.isExternalModuleReference(st.moduleReference) && st.moduleReference.expression.text === SHARED) shared.add(st.name.text);
      if (!ts.isImportDeclaration(st) || st.moduleSpecifier.text !== SHARED || !st.importClause) continue;
      const c = st.importClause, nb = c.namedBindings;
      if (c.name) shared.add(c.name.text);
      if (nb) (ts.isNamespaceImport(nb) ? [nb] : nb.elements).forEach(e => shared.add(e.name.text));
    }
    const rootName = e => {
      while (e && (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isSatisfiesExpression(e) || ts.isTypeAssertionExpression(e) || ts.isPropertyAccessExpression(e) || ts.isElementAccessExpression(e) || ts.isCallExpression(e) || ts.isNewExpression(e))) e = e.expression;
      while (e && ts.isQualifiedName(e)) e = e.left;
      return e && ts.isIdentifier(e) ? e.text : undefined;
    };
    const exported = st => !!st.modifiers?.some(m => m.kind === S.ExportKeyword);
    const heritage = n => !!n.heritageClauses?.some(h => h.types.some(t => carries(t.expression)));
    const carries = e => {
      while (e && (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isSatisfiesExpression(e) || ts.isTypeAssertionExpression(e))) e = e.expression;
      if (!e) return false;
      if (ts.isAwaitExpression(e)) return carries(e.expression);
      if (ts.isCallExpression(e) && (e.expression.kind === S.ImportKeyword || (ts.isIdentifier(e.expression) && e.expression.text === "require")) && e.arguments[0] && ts.isStringLiteralLike(e.arguments[0]) && e.arguments[0].text === SHARED) return true;
      if (shared.has(rootName(e))) return true;
      if (ts.isObjectLiteralExpression(e)) return e.properties.some(p => ts.isPropertyAssignment(p) ? carries(p.initializer) : ts.isShorthandPropertyAssignment(p) ? shared.has(p.name.text) : ts.isSpreadAssignment(p) && carries(p.expression));
      if (ts.isArrayLiteralExpression(e)) return e.elements.some(x => carries(ts.isSpreadElement(x) ? x.expression : x));
      if (ts.isCallExpression(e) && /^Object\.(freeze|assign)$/.test(e.expression.getText(sf))) return e.arguments.some(carries);
      if (ts.isConditionalExpression(e)) return carries(e.whenTrue) || carries(e.whenFalse);
      if (ts.isBinaryExpression(e)) return carries(e.left) || carries(e.right);
      return ts.isClassExpression(e) && heritage(e);
    };
    const typeCarries = t => !!t && ((ts.isTypeReferenceNode(t) && shared.has(rootName(t.typeName))) || (ts.isTypeQueryNode(t) && shared.has(rootName(t.exprName))) || ((ts.isUnionTypeNode(t) || ts.isIntersectionTypeNode(t)) && t.types.some(typeCarries)) || (ts.isParenthesizedTypeNode(t) && typeCarries(t.type)));
    const bound = b => ts.isIdentifier(b) ? [b.text] : (b.elements ?? []).flatMap(el => ts.isOmittedExpression(el) ? [] : bound(el.name));
    const tops = [];
    const collect = list => { for (const st of list) { tops.push(st); if (ts.isModuleDeclaration(st) && st.body && ts.isModuleBlock(st.body)) collect(st.body.statements); } };
    collect(sf.statements);
    for (let before = -1; before !== shared.size; ) {
      before = shared.size;
      for (const st of tops) {
        const names = [];
        if (ts.isVariableStatement(st)) for (const d of st.declarationList.declarations) { if (d.initializer && carries(d.initializer)) names.push(...bound(d.name)); }
        if (ts.isExpressionStatement(st) && ts.isBinaryExpression(st.expression) && st.expression.operatorToken.kind === S.EqualsToken && carries(st.expression.right)) names.push(...bound(st.expression.left.kind === S.Identifier ? st.expression.left : { elements: [] }));
        if (ts.isImportEqualsDeclaration(st) && !ts.isExternalModuleReference(st.moduleReference) && shared.has(rootName(st.moduleReference))) names.push(st.name.text);
        if ((ts.isClassDeclaration(st) || ts.isInterfaceDeclaration(st)) && st.name && heritage(st)) names.push(st.name.text);
        if (ts.isTypeAliasDeclaration(st) && typeCarries(st.type)) names.push(st.name.text);
        names.forEach(x => shared.add(x));
      }
    }
    const refers = e => {
      while (e && (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isSatisfiesExpression(e) || ts.isTypeAssertionExpression(e) || ts.isPropertyAccessExpression(e) || ts.isElementAccessExpression(e))) e = e.expression;
      return !!e && ts.isIdentifier(e) && shared.has(e.text);
    };
    const exposes = e => {
      while (e && (ts.isParenthesizedExpression(e) || ts.isAsExpression(e) || ts.isNonNullExpression(e) || ts.isSatisfiesExpression(e) || ts.isTypeAssertionExpression(e))) e = e.expression;
      if (!e) return false;
      if (refers(e) || (ts.isAwaitExpression(e) && carries(e))) return true;
      if (ts.isObjectLiteralExpression(e)) return e.properties.some(p => ts.isPropertyAssignment(p) ? exposes(p.initializer) : ts.isShorthandPropertyAssignment(p) ? shared.has(p.name.text) : ts.isSpreadAssignment(p) && exposes(p.expression));
      if (ts.isArrayLiteralExpression(e)) return e.elements.some(x => exposes(ts.isSpreadElement(x) ? x.expression : x));
      if (ts.isCallExpression(e) && /^Object\.(freeze|assign)$/.test(e.expression.getText(sf))) return e.arguments.some(exposes);
      return ts.isConditionalExpression(e) ? exposes(e.whenTrue) || exposes(e.whenFalse) : ts.isBinaryExpression(e) && (exposes(e.left) || exposes(e.right));
    };
    const hidden = m => ts.isPrivateIdentifier(m.name) || !!m.modifiers?.some(x => x.kind === S.PrivateKeyword || x.kind === S.ProtectedKeyword);
    const publicField = n => ts.isPropertyDeclaration(n) && !hidden(n) && !!n.initializer && ts.isClassLike(n.parent) && exposes(n.initializer);
    const republished = n =>
      (ts.isExportDeclaration(n) && !n.moduleSpecifier && !!n.exportClause && ts.isNamedExports(n.exportClause) && n.exportClause.elements.some(e => shared.has((e.propertyName ?? e.name).text)))
      || (ts.isExportAssignment(n) && carries(n.expression))
      || (ts.isVariableStatement(n) && exported(n) && n.declarationList.declarations.some(d => d.initializer && carries(d.initializer)))
      || ((ts.isClassDeclaration(n) || ts.isInterfaceDeclaration(n)) && exported(n) && heritage(n))
      || (ts.isTypeAliasDeclaration(n) && exported(n) && typeCarries(n.type))
      || (ts.isImportEqualsDeclaration(n) && exported(n) && !ts.isExternalModuleReference(n.moduleReference) && shared.has(rootName(n.moduleReference)));
    const visit = n => {
      if (republished(n)) say(`republishes ${SHARED}`);
      if (publicField(n)) say(`republishes ${SHARED} (a public class field holds it)`);
      if (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) { if (n.moduleSpecifier && ts.isStringLiteralLike(n.moduleSpecifier)) importOf(n.moduleSpecifier.text, n); }
      else if (ts.isImportEqualsDeclaration(n) && ts.isExternalModuleReference(n.moduleReference)) { const e = n.moduleReference.expression; if (ts.isStringLiteralLike(e)) importOf(e.text, n); else say("non-literal require()"); }
      else if (ts.isCallExpression(n) && (n.expression.kind === S.ImportKeyword || (ts.isIdentifier(n.expression) && n.expression.text === "require"))) {
        const kind = n.expression.kind === S.ImportKeyword ? "import" : "require";
        const arg = n.arguments[0];
        if (arg && ts.isStringLiteralLike(arg)) importOf(arg.text, n); else say(`non-literal ${kind}()`);
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

echo "✅ io-boundary: ${#files[@]} src/ modules keep effects in src/adapters/ (pino, node:fs, @opentelemetry/*, process); the rest import only relative paths, zod, result, interfaces, core-utils and the pure OpenTelemetry surface"
