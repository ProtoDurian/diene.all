using AtomiCloud.Diene.Problems;
using AtomiCloud.DotnetBase.App;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;

namespace AtomiCloud.DotnetBase.IntTest;

public class ProblemApp_Rfc9457RoundTrip
{
    private static readonly ProblemIdentity Identity = new("raichu", "dotnet", "notes", "api");
    private static readonly ErrorPortalOption Portal = new()
    {
        Scheme = "https",
        Host = "docs.raichu.cluster.atomi.cloud",
    };

    [Fact]
    public async Task It_should_render_registered_custom_and_guard_problems_end_to_end()
    {
        // Arrange
        await using var app = ProblemApp.Build(Identity, Portal, webHost => webHost.UseTestServer());
        var cancellationToken = TestContext.Current.CancellationToken;
        await app.StartAsync(cancellationToken);
        using var client = app.GetTestClient();

        // Act
        using var customResponse = await client.GetAsync("/notes/note-42", cancellationToken);
        using var guardResponse = await client.GetAsync("/guard/entity-42", cancellationToken);
        var custom = (await customResponse.Should().BeRfc9457()).Which;
        var guard = (await guardResponse.Should().BeRfc9457()).Which;

        // Assert
        custom.Should().HaveType(
            "https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/notes/api/v1/note_missing");
        custom.Should().HaveStatus(404);
        custom.Should().HaveData(new NoteMissing("note-42"));
        custom.Should().BeRecoverable(false);

        guard.Should().HaveType(
            "https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/notes/api/v1/entity_not_found");
        guard.Should().HaveStatus(404);
        guard.Should().HaveData(new EntityNotFound("string 'entity-42' was not found.", typeof(string), "entity-42"));
        guard.Should().BeRecoverable(false);
    }

    [Fact]
    public async Task It_should_render_the_generic_conflict_and_a_data_less_problem_end_to_end()
    {
        // Arrange
        await using var app = ProblemApp.Build(Identity, Portal, webHost => webHost.UseTestServer());
        var cancellationToken = TestContext.Current.CancellationToken;
        await app.StartAsync(cancellationToken);
        using var client = app.GetTestClient();

        // Act
        using var conflictResponse = await client.PostAsync("/notes/note-42", null, cancellationToken);
        using var sessionResponse = await client.GetAsync("/session", cancellationToken);
        var conflict = (await conflictResponse.Should().BeRfc9457()).Which;
        var session = (await sessionResponse.Should().BeRfc9457()).Which;

        // Assert
        conflict.Should().HaveType(
            "https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/notes/api/v1/conflict");
        conflict.Should().HaveStatus(409);
        conflict.Should().HaveData(new Conflict("ignored", "Note", "note-42"));
        conflict.Should().BeRecoverable(true);

        session.Should().HaveType(
            "https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/notes/api/v1/unauthenticated");
        session.Should().HaveStatus(401);
        session.Should().HaveNoData();
        session.Should().BeRecoverable(true);
    }

    [Fact]
    public async Task It_should_turn_an_uncatalogued_typed_problem_into_500()
    {
        // Arrange
        await using var app = ProblemApp.Build(Identity, Portal, webHost => webHost.UseTestServer());
        var cancellationToken = TestContext.Current.CancellationToken;
        await app.StartAsync(cancellationToken);
        using var client = app.GetTestClient();

        // Act
        using var response = await client.GetAsync("/unregistered", cancellationToken);
        var actual = (await response.Should().BeRfc9457()).Which;

        // Assert
        actual.Should().HaveType("about:blank");
        actual.Should().HaveStatus(500);
        actual.Should().BeRecoverable(false);
        actual.Should().HaveNoData();
    }
}
