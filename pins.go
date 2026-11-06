//go:build pins

// Package pins keeps pinned, not-yet-imported libraries in go.mod through go mod tidy.
package pins

import (
	_ "cloud.google.com/go/civil"
	_ "github.com/go-playground/validator/v10"
	_ "github.com/samber/lo"
	_ "github.com/sosodev/duration"
)
