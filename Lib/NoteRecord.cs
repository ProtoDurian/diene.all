namespace AtomiCloud.Diene.Note;

public record NoteRecord
{
    public required string Title { get; init; }

    public required string Body { get; init; }
}
