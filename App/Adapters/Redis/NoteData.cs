namespace AtomiCloud.DotnetBase.App.Adapters.Redis;

internal sealed record NoteData
{
    public required string Id { get; init; }

    public required string Title { get; init; }

    public required string Body { get; init; }
}
