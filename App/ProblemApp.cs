using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.App;

public static class ProblemApp
{
    public static WebApplication Build(
        ProblemIdentity identity,
        ErrorPortalOption portal,
        Action<IWebHostBuilder>? configureWebHost = null)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            ApplicationName = typeof(ProblemApp).Assembly.FullName,
            Args = ["--hostBuilder:reloadConfigOnChange=false"],
        });
        configureWebHost?.Invoke(builder.WebHost);
        var registeredServices = builder.Services.AddAtomiProblems(
            identity,
            portal,
            catalog => catalog
                .AddBaseline()
                .Add<NoteMissing>(404, false, new ProblemEndpoint("GET", "/notes/{id}")));
        if (!ReferenceEquals(registeredServices, builder.Services))
            throw new InvalidOperationException("Problem registration must preserve the service collection.");

        var app = builder.Build();
        app.UseExceptionHandler();
        app.MapGet("/notes/{id}", ThrowNoteMissing);
        app.MapGet("/guard/{id}", GuardMissingEntity);
        app.MapPost("/notes/{id}", ThrowNoteConflict);
        app.MapGet("/session", ThrowUnauthenticated);
        app.MapGet("/unregistered", ThrowUnregistered);
        return app;
    }

    private static IResult ThrowNoteMissing(string id) => throw new NoteMissing(id).ToException();

    private static IResult GuardMissingEntity(string id) =>
        ProblemGuard.NotFound<string>(null, id).Match<IResult>(
            value => Microsoft.AspNetCore.Http.Results.Ok(value),
            problem => throw problem.ToException());

    private static IResult ThrowNoteConflict(string id) =>
        throw new Conflict($"Note '{id}' already exists.", "Note", id).ToException();

    private static IResult ThrowUnauthenticated() => throw new Unauthenticated("Sign in to read notes.").ToException();

    private static IResult ThrowUnregistered() => throw new UnregisteredDemoProblem().ToException();
}
