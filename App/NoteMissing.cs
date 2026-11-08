using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.DotnetBase.App;

[Description("The requested note does not exist.")]
public sealed class NoteMissing : IDomainProblem
{
    public NoteMissing()
    {
    }

    public NoteMissing(string noteId)
    {
        NoteId = noteId ?? throw new ArgumentNullException(nameof(noteId));
        Detail = $"Note '{noteId}' does not exist.";
    }

    [JsonIgnore]
    public string Id => "note_missing";

    [JsonIgnore]
    public string Title => "Note Missing";

    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    [JsonIgnore]
    public string Version => "v1";

    [Description("The identifier of the note that was requested.")]
    public string NoteId { get; } = string.Empty;
}

internal sealed class UnregisteredDemoProblem : IDomainProblem
{
    [JsonIgnore]
    public string Id => "unregistered_demo";

    [JsonIgnore]
    public string Title => "Unregistered Demo";

    [JsonIgnore]
    public string Detail => "This problem intentionally exercises the uncatalogued-to-500 rule.";

    [JsonIgnore]
    public string Version => "v1";

    public string Marker => "catalog-loop";
}
