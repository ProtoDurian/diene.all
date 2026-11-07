using System.Collections.Concurrent;
using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.DotnetBase.SitTest;

/// <summary>One export request the receiver accepted.</summary>
/// <param name="Path">The request path, e.g. <c>/v1/traces</c>.</param>
/// <param name="ContentType">The request content type.</param>
/// <param name="Body">The raw request body.</param>
public sealed record OtlpRequest(string Path, string? ContentType, byte[] Body);

/// <summary>
/// A test-only OTLP/HTTP receiver on the fleet port 4318. Each instance binds a random
/// 127.x.y.z address, so parallel runs on one host share the port without colliding.
/// </summary>
public sealed class OtlpReceiver : IAsyncDisposable
{
    private static readonly string[] Paths = ["/v1/traces", "/v1/metrics", "/v1/logs"];

    private readonly WebApplication _app;
    private readonly ConcurrentQueue<OtlpRequest> _requests = new();
    private readonly SemaphoreSlim _arrived = new(0);

    private OtlpReceiver(WebApplication app, IPAddress address)
    {
        _app = app;
        Endpoint = new Uri($"http://{address}:{OtelHostExtensions.OtlpPort}");
    }

    /// <summary>The base endpoint to point an OTLP exporter at.</summary>
    public Uri Endpoint { get; }

    /// <summary>Every request accepted so far.</summary>
    public IReadOnlyList<OtlpRequest> Requests => [.. _requests];

    /// <summary>Starts a receiver, retrying on a fresh address if one is already taken.</summary>
    public static async Task<OtlpReceiver> StartAsync()
    {
        for (var attempt = 0; ; attempt++)
        {
            var address = RandomLoopback();
            var receiver = Create(address);
            try
            {
                await receiver._app.StartAsync(TestContext.Current.CancellationToken);
                return receiver;
            }
            catch (IOException) when (attempt < 8)
            {
                await receiver.DisposeAsync();
            }
        }
    }

    /// <summary>Waits until a request on <paramref name="path" /> arrives, or the timeout passes.</summary>
    public async Task<OtlpRequest?> WaitForAsync(string path, TimeSpan timeout)
    {
        using var deadline = new CancellationTokenSource(timeout);
        while (true)
        {
            var match = _requests.FirstOrDefault(request => request.Path == path);
            if (match is not null) return match;
            try
            {
                await _arrived.WaitAsync(deadline.Token);
            }
            catch (OperationCanceledException)
            {
                return _requests.FirstOrDefault(request => request.Path == path);
            }
        }
    }

    /// <inheritdoc />
    public async ValueTask DisposeAsync()
    {
        await _app.DisposeAsync();
        _arrived.Dispose();
    }

    private static OtlpReceiver Create(IPAddress address)
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseKestrel(kestrel => kestrel.Listen(address, OtelHostExtensions.OtlpPort));

        var app = builder.Build();
        var receiver = new OtlpReceiver(app, address);
        foreach (var path in Paths) app.MapPost(path, receiver.Accept);
        // Record stray requests too, so a wrong path fails a test instead of vanishing.
        app.MapFallback(async context =>
        {
            await receiver.Accept(context);
            context.Response.StatusCode = StatusCodes.Status404NotFound;
        });
        return receiver;
    }

    private async Task Accept(HttpContext context)
    {
        using var body = new MemoryStream();
        await context.Request.Body.CopyToAsync(body, context.RequestAborted);
        _requests.Enqueue(new OtlpRequest(context.Request.Path, context.Request.ContentType, body.ToArray()));
        _arrived.Release();
    }

    private static IPAddress RandomLoopback() =>
        new([127, (byte)Random.Shared.Next(1, 255), (byte)Random.Shared.Next(1, 255), (byte)Random.Shared.Next(1, 255)]);
}
