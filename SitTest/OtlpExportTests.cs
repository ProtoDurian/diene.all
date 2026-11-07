using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using OtelLoggerProvider = OpenTelemetry.Logs.LoggerProvider;
using OtelLoggerProviderExtensions = OpenTelemetry.Logs.LoggerProviderExtensions;

namespace AtomiCloud.DotnetBase.SitTest;

/// <summary>
/// Real OTLP/HTTP export from a host wired by <see cref="OtelHostExtensions.AddAtomiOtel(IHostApplicationBuilder, AppIdentity, OtelOption, IReadOnlyDictionary{string, string?}?)" />
/// to a loopback receiver on port 4318.
/// </summary>
public sealed class OtlpExportTests : IAsyncLifetime
{
    private const string Service = "sit-otel-export";
    private const string ProtobufContentType = "application/x-protobuf";
    private const int FlushMilliseconds = 10_000;
    private static readonly TimeSpan Wait = TimeSpan.FromSeconds(10);

    private static readonly AppIdentity Identity = new("lapras", "atomi", Service, "sit", "1.0.0");

    private OtlpReceiver _receiver = null!;

    public async ValueTask InitializeAsync() => _receiver = await OtlpReceiver.StartAsync();

    public async ValueTask DisposeAsync() => await _receiver.DisposeAsync();

    [Fact]
    public async Task Traces_WithOtlpEnabled_ExportsASpanOverHttpProtobuf()
    {
        // Arrange
        var option = Silent();
        option.Traces.Exporter.Otlp = Otlp(_receiver.Endpoint);
        using var host = Host(option, Empty());
        var provider = host.Services.GetRequiredService<TracerProvider>();
        var emitter = host.Services.GetRequiredService<ITraceEmitter>();
        var record = TraceRecord.Create("sit.request").Match(created => created, error => throw new InvalidOperationException(error.ToString()));

        // Act
        emitter.Emit(record).Should().BeOk();
        provider.ForceFlush(FlushMilliseconds);
        var request = await _receiver.WaitForAsync("/v1/traces", Wait);

        // Assert
        ShouldCarryTheService(request);
    }

    [Fact]
    public async Task Metrics_WithOtlpEnabled_ExportsAMeasurementOverHttpProtobuf()
    {
        // Arrange
        var option = Silent();
        option.Metrics.Exporter.Otlp = Otlp(_receiver.Endpoint);
        using var host = Host(option, Empty());
        var provider = host.Services.GetRequiredService<MeterProvider>();
        var metrics = host.Services.GetRequiredService<IMetricsCollector>();

        // Act
        metrics.Emit(new MetricRecord(DateTimeOffset.UtcNow, "sit.requests", MetricKind.Counter, 1.0)).Should().BeOk();
        provider.ForceFlush(FlushMilliseconds);
        var request = await _receiver.WaitForAsync("/v1/metrics", Wait);

        // Assert
        ShouldCarryTheService(request);
    }

    [Fact]
    public async Task Logs_WithOtlpEnabled_ExportsARecordOverHttpProtobuf()
    {
        // Arrange
        var option = Silent();
        option.Logs.Exporter.Otlp = Otlp(_receiver.Endpoint);
        using var host = Host(option, Empty());
        var provider = host.Services.GetRequiredService<OtelLoggerProvider>();
        var logger = host.Services.GetRequiredService<ILoggerSink>();

        // Act
        logger.Emit(new LogRecord(DateTimeOffset.UtcNow, LogLevel.Info, "sit served")).Should().BeOk();
        OtelLoggerProviderExtensions.ForceFlush(provider, FlushMilliseconds);
        var request = await _receiver.WaitForAsync("/v1/logs", Wait);

        // Assert
        ShouldCarryTheService(request);
    }

    [Fact]
    public async Task Defaults_WithEveryExporterOff_SendNothing()
    {
        // Arrange
        // The ops endpoint points at the receiver, so any OTLP exporter wired by default would reach it.
        var endpoint = _receiver.Endpoint.ToString();
        using var host = Host(new OtelOption(), Env(endpoint), endpoint);
        var traces = host.Services.GetRequiredService<TracerProvider>();
        var meters = host.Services.GetRequiredService<MeterProvider>();
        var logs = host.Services.GetRequiredService<OtelLoggerProvider>();
        var record = TraceRecord.Create("sit.request").Match(created => created, error => throw new InvalidOperationException(error.ToString()));

        // Act
        host.Services.GetRequiredService<ITraceEmitter>().Emit(record).Should().BeOk();
        host.Services.GetRequiredService<IMetricsCollector>()
            .Emit(new MetricRecord(DateTimeOffset.UtcNow, "sit.requests", MetricKind.Counter, 1.0)).Should().BeOk();
        host.Services.GetRequiredService<ILoggerSink>()
            .Emit(new LogRecord(DateTimeOffset.UtcNow, LogLevel.Info, "sit served")).Should().BeOk();
        traces.ForceFlush(FlushMilliseconds);
        meters.ForceFlush(FlushMilliseconds);
        OtelLoggerProviderExtensions.ForceFlush(logs, FlushMilliseconds);
        await Task.Delay(TimeSpan.FromSeconds(1), TestContext.Current.CancellationToken);

        // Assert
        _receiver.Requests.Should().BeEmpty();
    }

    private static OtelOption Silent() => new()
    {
        Logs = new LogsOption { Enabled = true },
        Metrics = new MetricsOption { Enabled = true },
        Traces = new TracesOption { Enabled = true, Sampler = new SamplerOption { Type = "always_on" } },
    };

    private static OtlpExporterOption Otlp(Uri endpoint) => new() { Enabled = true, Endpoint = endpoint.ToString() };

    private static Dictionary<string, string?> Empty() => new(StringComparer.Ordinal);

    private static Dictionary<string, string?> Env(string endpoint) =>
        new(StringComparer.Ordinal) { [OtelEnvironment.OtlpEndpointVariable] = endpoint };

    private static IHost Host(OtelOption option, IReadOnlyDictionary<string, string?> environment, string? sdkEndpoint = null)
    {
        var builder = Microsoft.Extensions.Hosting.Host.CreateApplicationBuilder();
        if (sdkEndpoint is not null) builder.Configuration[OtelEnvironment.OtlpEndpointVariable] = sdkEndpoint;
        builder.AddAtomiOtel(Identity, option, environment).Should().BeOk();
        return builder.Build();
    }

    private void ShouldCarryTheService(OtlpRequest? request)
    {
        request.Should().NotBeNull("the receiver saw {0}", string.Join(",", _receiver.Requests.Select(seen => seen.Path)));
        request!.ContentType.Should().Be(ProtobufContentType);
        request.Body.AsSpan().IndexOf(Encoding.UTF8.GetBytes(Service)).Should().BeGreaterThanOrEqualTo(0);
    }
}
