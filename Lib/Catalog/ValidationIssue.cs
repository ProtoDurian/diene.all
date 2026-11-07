using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>One failed validation rule at a path inside the request.</summary>
[Description("One failed validation rule at a path inside the request.")]
public sealed class ValidationIssue(IReadOnlyList<string> path, string message, string? code = null)
{
    /// <summary>Gets the path segments to the invalid value; empty for the whole request.</summary>
    [Description("The path segments to the invalid value; empty for the whole request.")]
    public IReadOnlyList<string> Path { get; } = [.. path ?? throw new ArgumentNullException(nameof(path))];

    /// <summary>Gets the human-readable validation message.</summary>
    [Description("The human-readable validation message.")]
    public string Message { get; } = message ?? throw new ArgumentNullException(nameof(message));

    /// <summary>Gets the optional machine-readable rule code.</summary>
    [Description("The optional machine-readable rule code.")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Code { get; } = code;
}
