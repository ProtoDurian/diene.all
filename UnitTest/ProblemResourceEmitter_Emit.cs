using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest;

public class ProblemResourceEmitter_Emit
{
    private static readonly ProblemIdentity Identity = new("lapras", "dotnet", "notes", "api");
    private static readonly ErrorPortalConfig Portal = new("https", "docs.example.test", Identity);

    [Fact]
    public void It_should_take_the_module_from_the_portal_or_accept_an_equal_explicit_module()
    {
        // Arrange
        var emitter = Emitter(Portal, catalog => catalog.Add<SampleProblem>(400, false));

        // Act
        var implicitModule = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));
        var explicitModule = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "api", "lapras", "v1"));
        var wrongModule = () => emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "web", "lapras", "v1"));
        var nullModule = () => new ProblemResourceIdentity("dotnet", "notes", null!, "lapras", "v1");

        // Assert
        implicitModule.Spec.Module.Should().Be("api");
        explicitModule.Spec.Module.Should().Be("api");
        explicitModule.Metadata.Should().Be(new ProblemResourceMetadata("notes.api.lapras.v1", "dotnet"));
        wrongModule.Should().Throw<ArgumentException>().WithMessage("*ErrorPortal identity*");
        nullModule.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_write_the_five_identity_fields_before_problems_in_contract_order()
    {
        // Arrange
        var emitter = Emitter(Portal, catalog => catalog.Add<SampleProblem>(400, false));
        var resource = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));

        // Act
        var spec = JsonNode.Parse(emitter.Serialize(resource))!["spec"]!.AsObject();

        // Assert
        spec.Select(member => member.Key).Should().Equal("platform", "service", "module", "landscape", "version", "problems");
        spec["module"]!.GetValue<string>().Should().Be("api");
    }

    [Fact]
    public void It_should_read_a_spec_without_a_module_as_an_empty_module()
    {
        // Arrange
        var emitter = Emitter(Portal, catalog => catalog.Add<SampleProblem>(400, false, new ProblemEndpoint("GET", "/sample")));
        var document = JsonNode.Parse(emitter.Serialize(emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"))))!;
        document["spec"]!.AsObject().Remove("module");

        // Act
        var resource = JsonSerializer.Deserialize<ProblemResource>(document.ToJsonString(), AtomiJson.DefaultOptions)!;

        // Assert
        resource.Spec.Module.Should().BeEmpty();
        resource.Spec.Service.Should().Be("notes");
        resource.Spec.Problems.Should().ContainSingle().Which.Endpoints.Should().Equal(new ProblemEndpoint("GET", "/sample"));
    }

    [Fact]
    public void It_should_join_name_segments_with_dots_so_dashed_segments_never_collide()
    {
        // Arrange
        var dashedService = new ErrorPortalConfig("https", "docs.example.test", new ProblemIdentity("lapras", "dotnet", "a-b", "c"));
        var dashedModule = new ErrorPortalConfig("https", "docs.example.test", new ProblemIdentity("lapras", "dotnet", "a", "b-c"));

        // Act
        var first = Emitter(dashedService, catalog => catalog.Add<SampleProblem>(400, false))
            .Emit(new ProblemResourceIdentity("dotnet", "a-b", "lapras", "v1"));
        var second = Emitter(dashedModule, catalog => catalog.Add<SampleProblem>(400, false))
            .Emit(new ProblemResourceIdentity("dotnet", "a", "lapras", "v1"));

        // Assert
        first.Metadata.Name.Should().Be("a-b.c.lapras.v1");
        second.Metadata.Name.Should().Be("a.b-c.lapras.v1");
        first.Metadata.Name.Should().NotBe(second.Metadata.Name);
    }

    [Theory]
    [InlineData("lapras", "dotnet", "notes_svc", "api", "service")]
    [InlineData("lapras", "dotnet", "Notes.Svc", "api", "service")]
    [InlineData("lapras", "dotnet", "NOTES_SVC", "api", "service")]
    [InlineData("lapras", "Dotnet_Core", "notes", "api", "platform")]
    [InlineData("lapras", "dotnet", "notes", "Api", "module")]
    [InlineData("Lapras", "dotnet", "notes", "api", "landscape")]
    [InlineData("lapras", "dotnet", "notes-", "api", "service")]
    public void It_should_refuse_identity_fields_that_are_not_already_DNS_labels(
        string landscape, string platform, string service, string module, string field)
    {
        // Arrange
        var portal = new ErrorPortalConfig("https", "docs.example.test", new ProblemIdentity(landscape, platform, service, module));
        var emitter = Emitter(portal, catalog => catalog.Add<SampleProblem>(400, false));

        // Act
        var act = () => emitter.Emit(new ProblemResourceIdentity(platform, service, landscape, "v1"));

        // Assert
        act.Should().Throw<ArgumentException>().WithMessage($"*{field}*DNS-1123 label*").Which.ParamName.Should().Be(field);
    }

    [Fact]
    public void It_should_refuse_a_version_that_is_not_a_DNS_label()
    {
        // Arrange
        var emitter = Emitter(Portal, catalog => catalog.Add<SampleProblem>(400, false));

        // Act
        var act = () => emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "V1"));

        // Assert
        act.Should().Throw<ArgumentException>().WithMessage("*version*DNS-1123 label*");
    }

    [Fact]
    public void It_should_refuse_a_joined_name_longer_than_a_DNS_subdomain()
    {
        // Arrange
        var service = new string('s', 63);
        var module = new string('m', 63);
        var landscape = new string('l', 63);
        var version = "v" + new string('1', 62);
        var portal = new ErrorPortalConfig("https", "docs.example.test", new ProblemIdentity(landscape, "dotnet", service, module));
        var emitter = Emitter(portal, catalog => catalog.Add<SampleProblem>(400, false));

        // Act
        var act = () => emitter.Emit(new ProblemResourceIdentity("dotnet", service, landscape, version));

        // Assert
        act.Should().Throw<ArgumentException>().WithMessage("*longer than 253*");
    }

    [Fact]
    public void It_should_refuse_to_emit_for_an_http_portal_while_its_type_URIs_still_build()
    {
        // Arrange
        var portal = new ErrorPortalConfig("http", "localhost:8080", Identity);
        var emitter = Emitter(portal, catalog => catalog.Add<SampleProblem>(400, false));

        // Act
        var act = () => emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));
        var typeUri = new ProblemTypeUriBuilder(portal).Build("v1", "sample_problem");

        // Assert
        act.Should().Throw<InvalidOperationException>().WithMessage("*https*");
        typeUri.AbsoluteUri.Should().Be("http://localhost:8080/docs/lapras/dotnet/notes/api/v1/sample_problem");
    }

    [Fact]
    public void It_should_reject_a_name_segment_longer_than_a_DNS_label()
    {
        // Arrange
        var service = new string('s', 64);
        var portal = new ErrorPortalConfig("https", "docs.example.test", new ProblemIdentity("lapras", "dotnet", service, "api"));
        var emitter = Emitter(portal, catalog => catalog.Add<SampleProblem>(400, false));

        // Act
        var act = () => emitter.Emit(new ProblemResourceIdentity("dotnet", service, "lapras", "v1"));

        // Assert
        act.Should().Throw<ArgumentException>().WithMessage("*DNS-1123 label*");
    }

    [Fact]
    public void It_should_publish_the_not_schema_for_every_problem_without_data()
    {
        // Arrange
        var emitter = Emitter(Portal, catalog => catalog.AddBaseline().Add<EmptyProblem>(400, false));

        // Act
        var resource = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));
        var schemas = resource.Spec.Problems.ToDictionary(entry => entry.Id, entry => entry.Schema.ToJsonString());

        // Assert
        schemas["unauthenticated"].Should().Be("""{"not":{}}""");
        schemas["unauthorized"].Should().Be("""{"not":{}}""");
        schemas["invalid_json"].Should().Be("""{"not":{}}""");
        schemas["empty_problem"].Should().Be("""{"not":{}}""");
        schemas["entity_not_found"].Should().NotBe("""{"not":{}}""");
    }

    [Fact]
    public void It_should_match_the_baseline_and_consumer_resource_snapshot()
    {
        // Arrange
        var emitter = Emitter(Portal, catalog => catalog
            .AddBaseline()
            .Add<SampleProblem>(422, true, new ProblemEndpoint("POST", "/sample")));
        var path = Path.Combine(AppContext.BaseDirectory, "Snapshots", "problem-resource-v1.json");
        var expected = JsonNode.Parse(File.ReadAllText(path));

        // Act
        var resource = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "api", "lapras", "v1"));
        var actual = JsonNode.Parse(emitter.Serialize(resource))!;

        // Assert
        JsonNode.DeepEquals(actual, expected).Should().BeTrue(actual.ToJsonString());
        var problems = actual["spec"]!["problems"]!.AsArray();
        problems.Select(entry => entry!["id"]!.GetValue<string>()).Should().BeInAscendingOrder(StringComparer.Ordinal)
            .And.Contain(["conflict", "entity_not_found", "invalid_json", "sample_problem", "unauthenticated", "unauthorized", "validation_error"]);
        problems.Should().OnlyContain(entry =>
            entry!.AsObject().Select(member => member.Key).SequenceEqual(new[] { "id", "type", "title", "status", "recoverable", "schema", "endpoints" }) &&
            entry["type"]!.GetValue<string>() ==
            $"https://docs.example.test/docs/lapras/dotnet/notes/api/v1/{entry["id"]!.GetValue<string>()}");
    }

    private static ProblemResourceEmitter Emitter(ErrorPortalConfig portal, Action<ProblemCatalogBuilder> register)
    {
        var typeUris = new ProblemTypeUriBuilder(portal);
        var builder = new ProblemCatalogBuilder();
        register(builder);
        var catalog = builder.Build();
        return new ProblemResourceEmitter(catalog, new ProblemExporter(catalog, typeUris), typeUris, portal);
    }
}
