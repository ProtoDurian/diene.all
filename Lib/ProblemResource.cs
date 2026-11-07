using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace AtomiCloud.Diene.Problems;

/// <summary>Identifies one platform/service/module/landscape/version Problem CR row.</summary>
public sealed record ProblemResourceIdentity(
    string Platform,
    string Service,
    string Landscape,
    string Version)
{
    /// <summary>Creates an identity that names its module explicitly.</summary>
    public ProblemResourceIdentity(string platform, string service, string module, string landscape, string version)
        : this(platform, service, landscape, version) =>
        Module = module ?? throw new ArgumentNullException(nameof(module));

    /// <summary>Gets the module, or null to take it from the ErrorPortal identity.</summary>
    public string? Module { get; init; }
}

/// <summary>A Kubernetes Problem custom resource.</summary>
public sealed record ProblemResource(
    string ApiVersion,
    string Kind,
    ProblemResourceMetadata Metadata,
    ProblemResourceSpec Spec);

/// <summary>Problem CR object metadata.</summary>
public sealed record ProblemResourceMetadata(string Name, string Namespace);

/// <summary>Problem CR specification.</summary>
public sealed record ProblemResourceSpec(
    [property: JsonPropertyOrder(1)] string Platform,
    [property: JsonPropertyOrder(2)] string Service,
    [property: JsonPropertyOrder(4)] string Landscape,
    [property: JsonPropertyOrder(5)] string Version,
    [property: JsonPropertyOrder(6)] IReadOnlyList<ProblemResourceEntry> Problems)
{
    /// <summary>Creates a specification that names its module.</summary>
    [JsonConstructor]
    public ProblemResourceSpec(
        string platform,
        string service,
        string module,
        string landscape,
        string version,
        IReadOnlyList<ProblemResourceEntry> problems)
        : this(platform, service, landscape, version, problems) =>
        Module = module ?? throw new ArgumentNullException(nameof(module));

    /// <summary>Gets the module that owns the problems.</summary>
    [JsonPropertyOrder(3)]
    public string Module { get; init; } = string.Empty;
}

/// <summary>One typed problem in a Problem CR.</summary>
public sealed record ProblemResourceEntry(
    string Id,
    string Type,
    string Title,
    int Status,
    bool Recoverable,
    JsonNode Schema,
    IReadOnlyList<ProblemEndpoint> Endpoints);
