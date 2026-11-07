using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>A request failed field or value validation.</summary>
[Description("The request contains one or more validation errors.")]
public sealed class ValidationError : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public ValidationError()
    {
    }

    /// <summary>Creates a populated validation problem from messages grouped by dotted field path.</summary>
    public ValidationError(string detail, IDictionary<string, string[]> errors)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        Errors = errors is null
            ? throw new ArgumentNullException(nameof(errors))
            : new Dictionary<string, string[]>(errors, StringComparer.Ordinal);
        Issues = Array.AsReadOnly([
            .. Errors.SelectMany(field => field.Value.Select(message =>
                new ValidationIssue(field.Key.Length == 0 ? [] : field.Key.Split('.'), message))),
        ]);
    }

    /// <summary>Creates a populated validation problem from structured issues.</summary>
    public ValidationError(string detail, IEnumerable<ValidationIssue> issues)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        ArgumentNullException.ThrowIfNull(issues);
        Issues = Array.AsReadOnly([.. issues.Select(issue => issue ?? throw new ArgumentException("Validation issues must not be null.", nameof(issues)))]);
        Errors = Issues
            .GroupBy(issue => string.Join('.', issue.Path), StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.Select(issue => issue.Message).ToArray(), StringComparer.Ordinal);
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "validation_error";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Validation Error";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the structured validation issues.</summary>
    [Description("The validation issues, each at a path inside the request.")]
    public IReadOnlyList<ValidationIssue> Issues { get; } = [];

    /// <summary>Gets validation messages grouped by dotted field path.</summary>
    [JsonIgnore]
    public IReadOnlyDictionary<string, string[]> Errors { get; } = new Dictionary<string, string[]>();
}
