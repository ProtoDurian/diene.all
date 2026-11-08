using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems.Catalog;

/// <summary>An entity conflicts with an existing unique value or state.</summary>
[Description("The entity conflicts with an existing unique value or state.")]
public sealed class Conflict : IDomainProblem
{
    /// <summary>Creates an empty instance for catalog registration and schema export.</summary>
    public Conflict()
    {
    }

    /// <summary>Creates a conflict problem whose entity type is the CLR type name.</summary>
    public Conflict(string detail, Type type, string id)
        : this(detail, type?.Name ?? throw new ArgumentNullException(nameof(type)), id)
    {
    }

    /// <summary>Creates a conflict problem for a named entity type.</summary>
    public Conflict(string detail, string entityType, string id)
    {
        Detail = detail ?? throw new ArgumentNullException(nameof(detail));
        EntityType = entityType ?? throw new ArgumentNullException(nameof(entityType));
        EntityId = id ?? throw new ArgumentNullException(nameof(id));
    }

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "conflict";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Conflict";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail { get; } = string.Empty;

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";

    /// <summary>Gets the conflicting entity type.</summary>
    [Description("The type of the conflicting entity.")]
    [JsonInclude]
    [JsonRequired]
    public string EntityType { get; private init; } = string.Empty;

    /// <summary>Gets the conflicting entity identifier, serialized as <c>id</c>.</summary>
    [Description("The identifier of the conflicting entity.")]
    [JsonInclude]
    [JsonRequired]
    [JsonPropertyName("id")]
    [JsonPropertyOrder(1)]
    public string EntityId { get; private init; } = string.Empty;
}
