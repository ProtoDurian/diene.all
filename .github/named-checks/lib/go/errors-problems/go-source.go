//go:build ignore

// Prints facts about Go sources for the named checks of this directory, one
// "<path>\t<FACT> <value>" line each. It tokenizes with go/scanner, so comments
// never count and formatting (spacing, line breaks, raw vs interpreted strings)
// does not matter.
//
//	uri    DOCS when a string literal holds a `docs` path segment; SEG <name>
//	       for each type-URI segment named by an identifier (any case).
//	ids    ID <value> for each literal bound to an `ID` field or `"id"` key;
//	       STR <value> for every string literal (newlines escaped).
//	idents IDENT <name> for each exported identifier.
//
// Usage: go run go-source.go <mode> <root> <path>...
package main

import (
	"fmt"
	"go/scanner"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

type tok struct {
	kind token.Token
	text string
}

func tokens(src []byte) []tok {
	var s scanner.Scanner
	fset := token.NewFileSet()
	s.Init(fset.AddFile("", fset.Base(), len(src)), src, nil, 0)
	var out []tok
	for {
		_, kind, lit := s.Scan()
		if kind == token.EOF {
			return out
		}
		text := lit
		if kind == token.STRING {
			if v, err := strconv.Unquote(lit); err == nil {
				text = v
			}
		}
		out = append(out, tok{kind, text})
	}
}

func main() {
	mode, root, paths := os.Args[1], os.Args[2], os.Args[3:]
	docs := regexp.MustCompile(`(^|/)docs(/|$)`)
	segments := []string{"scheme", "host", "landscape", "platform", "service", "module", "version", "id"}
	for _, path := range paths {
		src, err := os.ReadFile(filepath.Join(root, path))
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		ts := tokens(src)
		emit := func(fact string) { fmt.Printf("%s\t%s\n", path, fact) }
		switch mode {
		case "uri":
			named := map[string]bool{}
			for _, t := range ts {
				if t.kind == token.STRING && docs.MatchString(t.text) && !named["DOCS"] {
					named["DOCS"] = true
					emit("DOCS")
				}
				if t.kind == token.IDENT {
					for _, seg := range segments {
						if strings.EqualFold(t.text, seg) && !named[seg] {
							named[seg] = true
							emit("SEG " + seg)
						}
					}
				}
			}
		case "ids":
			for i, t := range ts {
				if t.kind == token.STRING {
					emit("STR " + strings.ReplaceAll(t.text, "\n", `\n`))
				}
				if i+2 >= len(ts) || ts[i+1].kind != token.COLON || ts[i+2].kind != token.STRING {
					continue
				}
				field := t.kind == token.IDENT && t.text == "ID" && (i == 0 || ts[i-1].kind != token.PERIOD)
				key := t.kind == token.STRING && t.text == "id"
				if field || key {
					emit("ID " + ts[i+2].text)
				}
			}
		case "idents":
			for _, t := range ts {
				if t.kind == token.IDENT && unicode.IsUpper([]rune(t.text)[0]) {
					emit("IDENT " + t.text)
				}
			}
		default:
			fmt.Fprintf(os.Stderr, "go-source.go: unknown mode %q (uri | ids | idents)\n", mode)
			os.Exit(2)
		}
	}
}
