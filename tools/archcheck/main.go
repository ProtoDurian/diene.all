package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
)

const controllersDir = "adapters/operator/controllers"

// Arithmetic or magnitude comparison in controllers is a business decision; == and != are allowed.
var forbidden = map[token.Token]string{
	token.MUL: "*", token.QUO: "/", token.REM: "%",
	token.LSS: "<", token.GTR: ">", token.LEQ: "<=", token.GEQ: ">=",
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "❌ operator architecture: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("✅ operator thin-controller boundary passed")
}

func run() error {
	entries, err := os.ReadDir(controllersDir)
	if err != nil {
		return fmt.Errorf("read %s: %w", controllersDir, err)
	}

	fset := token.NewFileSet()
	delegates := false
	var violations []string

	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		path := filepath.Join(controllersDir, name)
		file, perr := parser.ParseFile(fset, path, nil, 0)
		if perr != nil {
			return fmt.Errorf("parse %s: %w", path, perr)
		}

		ast.Inspect(file, func(n ast.Node) bool {
			switch node := n.(type) {
			case *ast.SelectorExpr:
				if ident, ok := node.X.(*ast.Ident); ok && ident.Name == "reconcile" && node.Sel.Name == "Decide" {
					delegates = true
				}
			case *ast.BinaryExpr:
				if op, ok := forbidden[node.Op]; ok {
					violations = append(violations,
						fmt.Sprintf("%s: inline decision operator %q (business logic belongs in lib/operator/reconcile)",
							fset.Position(node.Pos()), op))
				}
			default:
			}
			return true
		})
	}

	if !delegates {
		violations = append(violations,
			controllersDir+": controllers must delegate to reconcile.Decide (thin-controller boundary)")
	}
	if len(violations) > 0 {
		return fmt.Errorf("thin-controller boundary violated:\n  %s", strings.Join(violations, "\n  "))
	}
	return nil
}
