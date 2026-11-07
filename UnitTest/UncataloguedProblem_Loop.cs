using System.Text.Json;
using System.Text.Json.Nodes;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using FluentAssertions;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.DotnetBase.UnitTest;

public class UncataloguedProblem_Loop
{
    private static readonly ProblemIdentity Identity = new("lapras", "dotnet", "notes", "api");
    private static readonly ErrorPortalOption Portal = new() { Scheme = "https", Host = "docs.example.test" };
    private static readonly ProblemResourceIdentity Row = new("dotnet", "notes", "api", "lapras", "v1");

    [Fact]
    public async Task It_should_render_an_uncatalogued_problem_as_a_plain_logged_500()
    {
        // Arrange
        var logger = new CapturingLogger<ProblemCatalog>();
        using var provider = Provider(logger, catalog => catalog.AddBaseline());

        // Act
        var (status, body) = await Render(provider, new SampleProblem("leak"));
        var resource = provider.GetRequiredService<ProblemResourceEmitter>().Emit(Row);

        // Assert
        status.Should().Be(500);
        body["type"]!.GetValue<string>().Should().Be("about:blank");
        body["status"]!.GetValue<int>().Should().Be(500);
        body["recoverable"]!.GetValue<bool>().Should().BeFalse();
        body.Should().NotContainKey("data");
        logger.Levels.Should().ContainSingle().Which.Should().Be(LogLevel.Error);
        logger.Messages.Single().Should().Contain(typeof(SampleProblem).FullName).And.Contain("v1/sample_problem");
        resource.Spec.Problems.Should().NotContain(entry => entry.Id == "sample_problem");
    }

    [Fact]
    public async Task It_should_publish_the_same_row_on_both_channels_once_the_problem_is_catalogued()
    {
        // Arrange
        var logger = new CapturingLogger<ProblemCatalog>();
        using var provider = Provider(logger, catalog => catalog
            .AddBaseline()
            .Add<SampleProblem>(422, true, new ProblemEndpoint("GET", "/sample/{id}")));
        var emitter = provider.GetRequiredService<ProblemResourceEmitter>();
        var exporter = provider.GetRequiredService<IProblemExporter>();

        // Act
        var (status, body) = await Render(provider, new SampleProblem("now-known"));
        var resource = emitter.Emit(Row);
        var serialized = JsonNode.Parse(emitter.Serialize(resource))!["spec"]!["problems"]!.AsArray();
        var exported = exporter.ExportAll().OrderBy(export => export.Id, StringComparer.Ordinal).ToArray();

        // Assert
        status.Should().Be(422);
        logger.Messages.Should().BeEmpty();
        var entry = resource.Spec.Problems.Should().ContainSingle(candidate => candidate.Id == "sample_problem").Which;
        body["type"]!.GetValue<string>().Should().Be(entry.Type);
        body["data"]!["value"]!.GetValue<string>().Should().Be("now-known");
        serialized.Should().HaveCount(exported.Length);
        for (var index = 0; index < exported.Length; index++)
        {
            var row = JsonSerializer.SerializeToNode(exported[index], AtomiJson.DefaultOptions);
            JsonNode.DeepEquals(serialized[index], row).Should().BeTrue(exported[index].Id);
        }
    }

    [Fact]
    public async Task It_should_omit_data_for_a_catalogued_problem_without_data()
    {
        // Arrange
        using var provider = Provider(new CapturingLogger<ProblemCatalog>(), catalog => catalog.AddBaseline());

        // Act
        var (status, body) = await Render(provider, new Unauthenticated("sign in"));

        // Assert
        status.Should().Be(401);
        body["type"]!.GetValue<string>().Should().EndWith("/v1/unauthenticated");
        body["recoverable"]!.GetValue<bool>().Should().BeTrue();
        body.Should().NotContainKey("data");
    }

    private static ServiceProvider Provider(ILogger<ProblemCatalog> logger, Action<ProblemCatalogBuilder> catalog)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddAtomiProblems(Identity, Portal, catalog);
        services.AddSingleton(logger);
        return services.BuildServiceProvider();
    }

    private static async Task<(int Status, JsonObject Body)> Render(IServiceProvider provider, IDomainProblem problem)
    {
        var handler = provider.GetServices<IExceptionHandler>().OfType<DomainProblemExceptionHandler>().Single();
        var context = new DefaultHttpContext { RequestServices = provider };
        context.Request.Path = "/sample/1";
        context.Response.Body = new MemoryStream();
        await handler.TryHandleAsync(context, problem.ToException(), TestContext.Current.CancellationToken);
        context.Response.Body.Position = 0;
        var body = await JsonNode.ParseAsync(context.Response.Body, cancellationToken: TestContext.Current.CancellationToken);
        return (context.Response.StatusCode, body!.AsObject());
    }
}
