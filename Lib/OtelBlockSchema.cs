using System.Reflection;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The engine-owned JSON Schema for the <c>otel:</c> block. The otel engine owns
/// the shape of its own block and ships it as a resource;
/// <c>AtomiCloud.Diene.Config</c> reads it to validate a service-composed root
/// without ever hard-coding these keys.
/// </summary>
public static class OtelBlockSchema
{
    /// <summary>The resource name the schema is embedded under.</summary>
    public const string ResourceName = "AtomiCloud.Diene.Otel.otel-block.schema.json";

    private static readonly Lazy<string> Lazy = new(Load);

    /// <summary>The schema document, as JSON text.</summary>
    public static string Json => Lazy.Value;

    private static string Load()
    {
        // Embedded by Lib.csproj: a missing resource is a build bug, so no null branch.
        using var stream = typeof(OtelBlockSchema).GetTypeInfo().Assembly.GetManifestResourceStream(ResourceName)!;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
