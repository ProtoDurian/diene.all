package note_test

// DOMAIN WIRING: replaceable Note sample examples.
import (
	"context"
	"fmt"

	"github.com/ProtoDurian/diene.go-lib/lib/note"
	"github.com/ProtoDurian/diene.go-lib/testhelper"
)

func ExampleKeyComposer_Slug() {
	fmt.Println(note.NewKeyComposer("notes").Slug("Living  Documentation"))
	// Output: living-documentation
}

func ExampleKeyComposer_Compose() {
	fmt.Println(note.NewKeyComposer("notes").Compose("living-documentation"))
	// Output: notes:living-documentation
}

func ExampleService_Create() {
	service := note.NewService(testhelper.NewMemoryStore(), note.NewKeyComposer("notes"))
	created, _ := service.Create(context.Background(), "Living Documentation", "examples compile as consumer code")
	loaded, _ := service.Load(context.Background(), created.Slug)
	fmt.Println(loaded.Slug, "=", loaded.Body)
	// Output: living-documentation = examples compile as consumer code
}

// END DOMAIN WIRING
