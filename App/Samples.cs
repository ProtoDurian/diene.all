using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;
using Microsoft.Extensions.Logging.Abstractions;

namespace AtomiCloud.DotnetBase.App;

public static class Samples
{
    public static string RunAll(ProblemIdentity identity, ErrorPortalOption portal)
    {
        var portalConfig = new ErrorPortalConfig(portal.Scheme, portal.Host, identity);
        IProblemTypeUriBuilder typeUris = new ProblemTypeUriBuilder(portalConfig);
        var catalog = new ProblemCatalogBuilder()
            .AddBaseline()
            .AddFromAssembly(
                typeof(NoteMissing).Assembly,
                type => type == typeof(NoteMissing),
                _ => 404,
                _ => false,
                _ => [new ProblemEndpoint("GET", "/notes/{id}")])
            .Build(NullLogger<ProblemCatalog>.Instance);

        var noteMissing = new NoteMissing("note-42");
        _ = catalog.All;
        _ = catalog.Find(noteMissing.Version, noteMissing.Id);
        _ = catalog.StatusOf(noteMissing);
        _ = typeUris.Build(noteMissing.Version, noteMissing.Id);
        _ = noteMissing.ToException();
        Result<string, IDomainProblem> failed = noteMissing.ToErr<string>();
        _ = failed.IsFailure();

        _ = ProblemGuard.NotNull("value", () => noteMissing);
        _ = ProblemGuard.Require(true, () => noteMissing);
        _ = ProblemGuard.NotFound<string>(null, "missing");

        var entityNotFound = new EntityNotFound("missing", typeof(string), "one");
        var namedNotFound = new EntityNotFound("missing", "Note", "two");
        var conflict = new Conflict("taken", typeof(string), "one");
        var namedConflict = new Conflict("taken", "Note", "two");
        var issueValidation = new ValidationError(
            "invalid",
            [new ValidationIssue(["address", "city"], "unknown", "enum"), new ValidationIssue([], "empty body")]);
        var multipleEntityNotFound = new MultipleEntityNotFound("missing", typeof(string), ["one"], ["two"]);
        var entityConflict = new EntityConflict("conflict", typeof(string));
        var validationError = new ValidationError(
            "invalid",
            new Dictionary<string, string[]> { ["name"] = ["required"] });
        var unauthorized = new Unauthorized("forbidden", ["notes:read"], ["notes:write"]);
        var invalidJson = new InvalidJson("invalid", "{");
        IDomainProblem[] baselineSamples =
        [
            entityNotFound,
            multipleEntityNotFound,
            entityConflict,
            conflict,
            namedConflict,
            namedNotFound,
            issueValidation,
            validationError,
            unauthorized,
            new Unauthenticated("sign in"),
            invalidJson
        ];
        _ = baselineSamples.Select(problem => problem.Id).ToArray();

        IProblemExporter exporter = new ProblemExporter(catalog, typeUris);
        _ = exporter.Export(catalog.All[0]);
        _ = exporter.ExportAll();
        var emitter = new ProblemResourceEmitter(catalog, exporter, typeUris, portalConfig);
        var resource = emitter.Emit(new ProblemResourceIdentity(
            identity.Platform,
            identity.Service,
            identity.Module,
            identity.Landscape,
            "v1"));
        var implicitModule = emitter.Emit(new ProblemResourceIdentity(
            identity.Platform,
            identity.Service,
            identity.Landscape,
            "v1"));
        var resourceJson = emitter.Serialize(resource);
        var resourceEntry = resource.Spec.Problems[0];

        var envelope = new Problem
        {
            Type = typeUris.Build(noteMissing.Version, noteMissing.Id).AbsoluteUri,
            Title = noteMissing.Title,
            Status = 404,
            Detail = noteMissing.Detail,
            Instance = "/notes/note-42",
            Recoverable = false,
            Data = JsonSerializer.SerializeToNode(noteMissing, AtomiJson.DefaultOptions),
            Extensions = new Dictionary<string, JsonElement>
            {
                ["traceId"] = JsonSerializer.SerializeToElement("demo-trace"),
            },
        };
        var envelopeJson = JsonSerializer.Serialize(envelope, AtomiJson.DefaultOptions);
        _ = JsonSerializer.Deserialize<Problem>(envelopeJson, AtomiJson.DefaultOptions);

        var payloadSummary =
            $"{noteMissing.NoteId}:{entityNotFound.EntityType}:{entityNotFound.EntityId}:{entityNotFound.RequestIdentifier}:{entityNotFound.TypeName}:" +
            $"{conflict.EntityType}:{conflict.EntityId}:{issueValidation.Issues.Count}:{issueValidation.Issues[0].Code}:" +
            $"{string.Join('.', issueValidation.Issues[0].Path)}:{issueValidation.Issues[1].Message}:" +
            $"{entityNotFound.AssemblyQualifiedName.Length}:{multipleEntityNotFound.RequestIdentifiers.Count}:" +
            $"{multipleEntityNotFound.FoundRequestIdentifiers.Count}:{multipleEntityNotFound.TypeName}:" +
            $"{multipleEntityNotFound.AssemblyQualifiedName.Length}:{entityConflict.TypeName}:" +
            $"{entityConflict.AssemblyQualifiedName.Length}:{validationError.Errors.Count}:" +
            $"{unauthorized.Granted.Count}:{unauthorized.Required.Count}:{invalidJson.InvalidString}:" +
            $"{new UnregisteredDemoProblem().Marker}";
        var resourceSummary =
            $"{resource.ApiVersion}:{resource.Kind}:{resource.Metadata.Name}:{resource.Metadata.Namespace}:" +
            $"{resource.Spec.Platform}:{resource.Spec.Service}:{resource.Spec.Module}:{implicitModule.Spec.Module}:{resource.Spec.Landscape}:{resource.Spec.Version}:" +
            $"{resourceEntry.Id}:{resourceEntry.Type}:{resourceEntry.Title}:{resourceEntry.Status}:" +
            $"{resourceEntry.Recoverable}:{resourceEntry.Schema.ToJsonString().Length}:{resourceEntry.Endpoints.Count}";

        return $"{catalog.All.Count} problems; {resource.Spec.Problems.Count} CR entries; {resourceJson.Length} JSON bytes; portal enabled={portal.Enabled}; key={ErrorPortalOption.Key}; payload={payloadSummary}; resource={resourceSummary}";
    }
}
