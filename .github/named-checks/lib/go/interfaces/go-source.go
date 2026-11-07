//go:build ignore

// Prints facts about Go sources for the named checks of this directory, one
// "<path>\t<FACT> <value>..." line each. It parses with the stdlib go/parser
// (no type-check, no build, no module download), so comments, formatting and
// import aliases never change the answer.
//
//	PACKAGE <name>             the package clause
//	IMPORT <path> <name>       each import; name is the alias, the default
//	                           package name (last path element) or "." / "_"
//	IFACE <type> <method>      each method of an interface type declaration
//	METHOD <recv> <name>       each method declaration (any receiver)
//	FUNC <name>                each top-level function declaration
//	TYPE <name>                each top-level type declaration
//	REF <import path> <name>   each selector <import>.<name> (a call, a value
//	                           or a func reference), resolved through the
//	                           file's own import names
//
// Usage: go run go-source.go <root> <path>...
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
)

func recvName(expr ast.Expr) string {
	switch t := expr.(type) {
	case *ast.StarExpr:
		return recvName(t.X)
	case *ast.IndexExpr:
		return recvName(t.X)
	case *ast.IndexListExpr:
		return recvName(t.X)
	case *ast.Ident:
		return t.Name
	}
	return "?"
}

func defaultName(importPath string) string {
	name := path.Base(importPath)
	// gopkg.in/yaml.v3 -> yaml; foo/v2 -> foo
	if i := strings.Index(name, "."); i > 0 && strings.HasPrefix(importPath, "gopkg.in/") {
		name = name[:i]
	}
	if len(name) > 1 && name[0] == 'v' && strings.Trim(name[1:], "0123456789") == "" {
		name = path.Base(path.Dir(importPath))
	}
	return strings.ReplaceAll(name, "-", "_")
}

func main() {
	root, paths := os.Args[1], os.Args[2:]
	for _, p := range paths {
		fset := token.NewFileSet()
		file, err := parser.ParseFile(fset, filepath.Join(root, p), nil, parser.SkipObjectResolution)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		emit := func(format string, args ...any) { fmt.Printf("%s\t%s\n", p, fmt.Sprintf(format, args...)) }
		emit("PACKAGE %s", file.Name.Name)
		imports := map[string]string{}
		for _, spec := range file.Imports {
			importPath, _ := strconv.Unquote(spec.Path.Value)
			name := defaultName(importPath)
			if spec.Name != nil {
				name = spec.Name.Name
			}
			imports[name] = importPath
			emit("IMPORT %s %s", importPath, name)
		}
		for _, decl := range file.Decls {
			switch d := decl.(type) {
			case *ast.FuncDecl:
				if d.Recv != nil && len(d.Recv.List) > 0 {
					emit("METHOD %s %s", recvName(d.Recv.List[0].Type), d.Name.Name)
				} else {
					emit("FUNC %s", d.Name.Name)
				}
			case *ast.GenDecl:
				for _, spec := range d.Specs {
					ts, ok := spec.(*ast.TypeSpec)
					if !ok {
						continue
					}
					emit("TYPE %s", ts.Name.Name)
					if it, ok := ts.Type.(*ast.InterfaceType); ok {
						for _, m := range it.Methods.List {
							if _, isFunc := m.Type.(*ast.FuncType); !isFunc {
								continue
							}
							for _, n := range m.Names {
								emit("IFACE %s %s", ts.Name.Name, n.Name)
							}
						}
					}
				}
			}
		}
		ast.Inspect(file, func(n ast.Node) bool {
			sel, ok := n.(*ast.SelectorExpr)
			if !ok {
				return true
			}
			if x, ok := sel.X.(*ast.Ident); ok {
				if importPath, ok := imports[x.Name]; ok {
					emit("REF %s %s", importPath, sel.Sel.Name)
				}
			}
			return true
		})
	}
}
