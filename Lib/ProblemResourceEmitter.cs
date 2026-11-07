using System.Text.Json;
using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.CoreUtils.Json;

namespace AtomiCloud.Diene.Problems;

/// <summary>Emits deterministic Problem custom resources from a registered catalog.</summary>
public sealed class ProblemResourceEmitter(
    IProblemCatalog catalog,
    IProblemExporter exporter,
    IProblemTypeUriBuilder typeUris,
    ErrorPortalConfig portal)
{
    private const int DnsLabelMax = 63;

    private readonly IProblemCatalog _catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));
    private readonly IProblemExporter _exporter = exporter ?? throw new ArgumentNullException(nameof(exporter));
    private readonly IProblemTypeUriBuilder _typeUris = typeUris ?? throw new ArgumentNullException(nameof(typeUris));
    private readonly ErrorPortalConfig _portal = portal ?? throw new ArgumentNullException(nameof(portal));

    /// <summary>Emits one Problem custom resource for a single catalog version.</summary>
    public ProblemResource Emit(ProblemResourceIdentity identity)
    {
        ArgumentNullException.ThrowIfNull(identity);
        if (_portal.Scheme != "https")
            throw new InvalidOperationException($"Problem resources need an https ErrorPortal; received {_portal.Scheme}.");
        ValidateIdentity(identity);
        var module = _portal.Identity.Module;

        var descriptors = _catalog.All
            .Where(descriptor => string.Equals(descriptor.Version, identity.Version, StringComparison.Ordinal))
            .ToArray();
        if (descriptors.Length == 0)
            throw new ArgumentException($"Problem catalog does not contain requested version '{identity.Version}'.", nameof(identity));

        var entries = descriptors
            .OrderBy(descriptor => descriptor.Id, StringComparer.Ordinal)
            .Select(descriptor => ToResourceEntry(descriptor, _exporter.Export(descriptor)))
            .ToArray();
        string[] segments = [identity.Service, module, identity.Landscape, identity.Version];
        var name = string.Join('.', segments.Select(DnsLabel));

        return new ProblemResource(
            "atomi.cloud/v1alpha1",
            "Problem",
            new ProblemResourceMetadata(name, identity.Platform),
            new ProblemResourceSpec(
                identity.Platform,
                identity.Service,
                module,
                identity.Landscape,
                identity.Version,
                Array.AsReadOnly(entries)));
    }

    /// <summary>Serializes a Problem custom resource as canonical JSON, which is valid YAML 1.2.</summary>
    public string Serialize(ProblemResource resource)
    {
        ArgumentNullException.ThrowIfNull(resource);
        return JsonSerializer.Serialize(resource, AtomiJson.DefaultOptions);
    }

    private static string DnsLabel(string segment)
    {
        var label = Slug.Slugify(segment);
        if (label.Length is 0 or > DnsLabelMax)
            throw new ArgumentException($"Problem resource name segment '{segment}' is not a DNS-1123 label after slugifying.", nameof(segment));
        return label;
    }

    private ProblemResourceEntry ToResourceEntry(ProblemDescriptor descriptor, ProblemExport export)
    {
        var expectedType = _typeUris.Build(descriptor.Version, descriptor.Id).AbsoluteUri;
        if (export.Type != expectedType)
            throw new InvalidOperationException($"Exported type URI for {descriptor.Version}/{descriptor.Id} does not match the configured ErrorPortal.");

        return new ProblemResourceEntry(
            export.Id,
            export.Type,
            export.Title,
            export.Status,
            export.Recoverable,
            export.Schema.DeepClone(),
            export.Endpoints);
    }

    private void ValidateIdentity(ProblemResourceIdentity identity)
    {
        var expected = _portal.Identity;
        if (identity.Platform != expected.Platform ||
            identity.Service != expected.Service ||
            identity.Landscape != expected.Landscape ||
            (identity.Module is not null && identity.Module != expected.Module))
        {
            throw new ArgumentException("Problem resource identity must match its ErrorPortal identity.", nameof(identity));
        }
    }
}
