namespace AtomiCloud.DotnetBase.Lib.Note;

public record NotePrincipal
{
    public required string Id { get; init; }

    public required NoteRecord Record { get; init; }
}
