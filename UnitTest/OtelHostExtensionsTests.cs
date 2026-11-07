using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry.Exporter;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelHostExtensionsTests
{
    private static AppIdentity Identity { get; } = new("lapras", "atomi", "billing", "api", "1.2.3");

    private static HostApplicationBuilder Builder() => Host.CreateApplicationBuilder();

    private static OtelOption AllOn() => new()
    {
        Logs = new LogsOption { Exporter = Exporter() },
        Metrics = new MetricsOption { Exporter = Exporter() },
        Traces = new TracesOption { Exporter = Exporter() },
    };

    private static ExporterOption Exporter() => new()
    {
        Console = new ConsoleExporterOption { Enabled = true },
        Otlp = new OtlpExporterOption { Enabled = true, Endpoint = "http://collector:4318" },
    };

    private static OtelOption WithOtlp(string signal, OtlpExporterOption otlp)
    {
        var exporter = new ExporterOption { Otlp = otlp };
        return new OtelOption
        {
            Logs = new LogsOption { Exporter = signal == "logs" ? exporter : new ExporterOption() },
            Metrics = new MetricsOption { Exporter = signal == "metrics" ? exporter : new ExporterOption() },
            Traces = new TracesOption { Exporter = signal == "traces" ? exporter : new ExporterOption() },
        };
    }

    private static OtlpExporterOption Enabled(string endpoint = "http://collector:4318", string timeout = "PT10S") =>
        new() { Enabled = true, Endpoint = endpoint, Timeout = timeout };

    private static OtelHostExtensions.OtlpSettings Preflighted(
        OtlpExporterOption otlp,
        IReadOnlyDictionary<string, string?> environment) =>
        OtelHostExtensions.Preflight(otlp, environment).Should().BeOk().Which;

    [Fact]
    public void OtlpProtocol_IsPinnedFleetWide()
    {
        // Act
        var protocol = OtelHostExtensions.OtlpProtocol;

        // Assert
        protocol.Should().Be("http/protobuf");
    }

    [Fact]
    public void AddAtomiOtel_RegistersTheIdentityInstrumentationAndEverySeam()
    {
        // Arrange
        var builder = Builder();

        // Act
        var result = builder.AddAtomiOtel(Identity, new OtelOption(), Env.None);

        // Assert
        result.Should().BeOk();
        using var host = builder.Build();
        host.Services.GetRequiredService<AppIdentity>().Should().Be(Identity);
        host.Services.GetRequiredService<Instrumentation>().Identity.Should().Be(Identity);
        host.Services.GetRequiredService<ITraceEmitter>().Should().BeOfType<ActivityTraceEmitter>();
        host.Services.GetRequiredService<IMetricsCollector>().Should().BeOfType<OtelMetricsCollector>();
        host.Services.GetRequiredService<ILoggerSink>().Should().BeOfType<OtelLoggerSink>();
    }

    [Fact]
    public void AddAtomiOtel_WiresEverySignalWithEveryExporterOn()
    {
        // Arrange
        var builder = Builder();
        builder.AddAtomiOtel(Identity, AllOn(), Env.None).Should().BeOk();
        using var host = builder.Build();

        // Act
        // Resolving the providers is what runs every exporter-configuration callback.
        var meters = host.Services.GetRequiredService<MeterProvider>();
        var tracers = host.Services.GetRequiredService<TracerProvider>();
        var logged = host.Services.GetRequiredService<ILoggerSink>()
            .Emit(new LogRecord(DateTimeOffset.UnixEpoch, AtomiCloud.Diene.Interfaces.LogLevel.Info, "wired"));

        // Assert
        meters.Should().NotBeNull();
        tracers.Should().NotBeNull();
        logged.Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_BuildsACleanNoOpPipelineWhenEveryExporterIsOff()
    {
        // Arrange
        var builder = Builder();
        builder.AddAtomiOtel(Identity, new OtelOption(), Env.None).Should().BeOk();
        using var host = builder.Build();
        var record = TraceRecord.Create("demo").Should().BeOk().Which;

        // Act
        var result = host.Services.GetRequiredService<ITraceEmitter>().Emit(record);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_SkipsEverySignalWhenTheSdkIsDisabledButStillRegistersTheSeams()
    {
        // Arrange
        var builder = Builder();

        // Act
        var result = builder.AddAtomiOtel(Identity, AllOn(), Env.Of((OtelEnvironment.SdkDisabledVariable, "true")));

        // Assert
        result.Should().BeOk();
        using var host = builder.Build();
        host.Services.GetRequiredService<ITraceEmitter>().Should().NotBeNull();
    }

    [Fact]
    public void AddAtomiOtel_SkipsADisabledSignal()
    {
        // Arrange
        var option = new OtelOption
        {
            Logs = new LogsOption { Enabled = false },
            Metrics = new MetricsOption { Enabled = false },
            Traces = new TracesOption { Enabled = false },
        };

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_HonoursAnExporterOverrideFromTheEnvironment()
    {
        // Arrange
        var environment = Env.Of(
            (OtelEnvironment.LogsExporterVariable, "none"),
            (OtelEnvironment.MetricsExporterVariable, "console"),
            (OtelEnvironment.TracesExporterVariable, "otlp"));

        // Act
        var result = Builder().AddAtomiOtel(Identity, AllOn(), environment);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_RejectsABadMetricsInterval()
    {
        // Arrange
        var option = new OtelOption { Metrics = new MetricsOption { Interval = "every minute" } };

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("metrics interval");
    }

    [Fact]
    public void AddAtomiOtel_RejectsABadSamplerType()
    {
        // Arrange
        var option = new OtelOption { Traces = new TracesOption { Sampler = new SamplerOption { Type = "coin_flip" } } };

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Operation.Should().Be("sampler");
    }

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_RejectsABadOtlpTimeoutOnEverySignal(string signal)
    {
        // Arrange
        var option = WithOtlp(signal, Enabled(timeout: "ten seconds"));

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("timeout");
    }

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_RejectsABlankEndpointOnAnEnabledOtlpExporter(string signal)
    {
        // Arrange
        var option = WithOtlp(signal, Enabled(endpoint: "  "));

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("needs an endpoint");
    }

    [Theory]
    [InlineData("logs", "http://collector:4317")]
    [InlineData("metrics", "http://collector:4317")]
    [InlineData("traces", "http://collector:4317")]
    [InlineData("logs", "http://collector")]
    [InlineData("metrics", "https://collector")]
    [InlineData("traces", "http://collector:8080")]
    public void AddAtomiOtel_RejectsAnEndpointThatIsNotTheFleetPort(string signal, string endpoint)
    {
        // Arrange
        var option = WithOtlp(signal, Enabled(endpoint));

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain($":{OtelHostExtensions.OtlpPort}");
    }

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_AcceptsABlankEndpointWhenTheEnvironmentSuppliesOne(string signal)
    {
        // Arrange
        var option = WithOtlp(signal, Enabled(endpoint: ""));
        var environment = Env.Of((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318"));

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, environment);

        // Assert
        result.Should().BeOk();
    }

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_IgnoresAnInvalidOtlpBlockWhenThatExporterIsNotSelected(string signal)
    {
        // Arrange
        var option = WithOtlp(signal, new OtlpExporterOption { Enabled = false, Timeout = "ten seconds" });

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeOk();
    }

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void AddAtomiOtel_RejectsANonFleetProtocolOnAnEnabledOtlpExporter(string signal)
    {
        // Arrange
        var option = WithOtlp(
            signal,
            new OtlpExporterOption { Enabled = true, Endpoint = "http://c:4318", Protocol = "grpc" });

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("pinned");
    }

    [Fact]
    public void AddAtomiOtel_RejectsAnInvalidExporterSelectedOnlyByTheEnvironment()
    {
        // Arrange
        var option = WithOtlp("traces", new OtlpExporterOption { Enabled = false, Endpoint = "http://c:4317" });
        var environment = Env.Of((OtelEnvironment.TracesExporterVariable, "otlp"));

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, environment);

        // Assert
        result.Should().BeErr();
    }

    [Fact]
    public void AddAtomiOtel_LeavesTheHostUntouchedWhenALaterSignalFails()
    {
        // Arrange
        var builder = Builder();
        var option = WithOtlp("traces", Enabled("http://collector:4317"));
        option.Logs.Exporter.Otlp = Enabled();

        // Act
        var result = builder.AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr();
        using var host = builder.Build();
        host.Services.GetService<TracerProvider>().Should().BeNull();
        host.Services.GetService<MeterProvider>().Should().BeNull();
        host.Services.GetService<ITraceEmitter>().Should().BeNull("no seam is registered when planning fails");
        host.Services.GetService<Instrumentation>().Should().BeNull();
    }

    [Fact]
    public void AddAtomiOtel_RegistersEverySignalWhenTheWholePlanIsValid()
    {
        // Arrange
        var builder = Builder();

        // Act
        var result = builder.AddAtomiOtel(Identity, AllOn(), Env.None);

        // Assert
        result.Should().BeOk();
        using var host = builder.Build();
        host.Services.GetService<TracerProvider>().Should().NotBeNull();
        host.Services.GetService<MeterProvider>().Should().NotBeNull();
    }

    [Fact]
    public void AddAtomiOtel_RejectsANullBuilder()
    {
        // Act
        var act = () => OtelHostExtensions.AddAtomiOtel(null!, Identity, new OtelOption());

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void AddAtomiOtel_RejectsANullIdentity()
    {
        // Arrange
        var builder = Builder();

        // Act
        var act = () => builder.AddAtomiOtel(null!, new OtelOption());

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void AddAtomiOtel_RejectsANullOption()
    {
        // Arrange
        var builder = Builder();

        // Act
        var act = () => builder.AddAtomiOtel(Identity, (OtelOption)null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void AddAtomiOtel_RejectsANullConfiguration()
    {
        // Arrange
        var builder = Builder();

        // Act
        var act = () => builder.AddAtomiOtel(Identity, (IConfiguration)null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void AddAtomiOtel_ReadsTheBlockFromConfiguration()
    {
        // Arrange
        var builder = Builder();
        builder.Configuration.AddInMemoryCollection(
        [
            new("Otel:Traces:Sampler:Type", "always_off"),
            new("Otel:Metrics:Interval", "PT30S"),
        ]);

        // Act
        var result = builder.AddAtomiOtel(Identity, builder.Configuration, Env.None);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_TreatsAMissingSectionAsTheShippedDefaults()
    {
        // Arrange
        var configuration = new ConfigurationBuilder().Build();

        // Act
        var result = Builder().AddAtomiOtel(Identity, configuration, Env.None);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void AddAtomiOtel_ReadsTheProcessEnvironmentWhenNoneIsInjected()
    {
        // Act
        var result = Builder().AddAtomiOtel(Identity, new OtelOption());

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void OtlpPort_IsTheFleetHttpPort()
    {
        // Act
        var port = OtelHostExtensions.OtlpPort;

        // Assert
        port.Should().Be(4318);
    }

    [Fact]
    public void Preflight_ValidatesTheEndpointHeadersAndTimeout()
    {
        // Arrange
        var otlp = new OtlpExporterOption
        {
            Endpoint = " http://collector:4318 ",
            Timeout = "PT5S",
            Headers = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["x-tenant"] = "acme",
                ["x-env"] = "lapras",
            },
        };

        // Act
        var result = OtelHostExtensions.Preflight(otlp, Env.None);

        // Assert
        var settings = result.Should().BeOk().Which;
        settings.Endpoint.Should().BeSome().Which.Should().Be(new Uri("http://collector:4318"));
        settings.TimeoutMilliseconds.Should().Be(5000);
        settings.Headers.Should().BeSome().Which.Should().Contain("x-tenant=acme").And.Contain("x-env=lapras");
    }

    [Theory]
    [InlineData("PT0S")]
    [InlineData("P0D")]
    [InlineData("-PT1S")]
    [InlineData("P30D")]
    public void Preflight_RejectsATimeoutOutsideTheUsableMillisecondRange(string timeout)
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(timeout: timeout), Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("between 1ms");
    }

    [Theory]
    [InlineData("PT0.001S", 1)]
    [InlineData("PT10S", 10_000)]
    public void Preflight_AcceptsATimeoutAtTheEdgeOfTheUsableRange(string timeout, int expected)
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(timeout: timeout), Env.None);

        // Assert
        result.Should().BeOk().Which.TimeoutMilliseconds.Should().Be(expected);
    }

    [Theory]
    [InlineData("PT0S")]
    [InlineData("-PT1S")]
    [InlineData("P30D")]
    public void AddAtomiOtel_RejectsAMetricsIntervalOutsideTheUsableRange(string interval)
    {
        // Arrange
        var option = new OtelOption { Metrics = new MetricsOption { Interval = interval } };

        // Act
        var result = Builder().AddAtomiOtel(Identity, option, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("metrics interval");
    }

    [Theory]
    [InlineData("PT0.001S", 1)]
    [InlineData("PT1M", 60_000)]
    public void Milliseconds_ReducesAValidDurationToWholeMilliseconds(string value, int expected)
    {
        // Act
        var result = OtelHostExtensions.Milliseconds(value, "interval");

        // Assert
        result.Should().BeOk().Which.Should().Be(expected);
    }

    [Fact]
    public void Milliseconds_PropagatesAParseFailure()
    {
        // Act
        var result = OtelHostExtensions.Milliseconds("60s", "interval");

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("ISO 8601");
    }

    [Fact]
    public void Milliseconds_RejectsADurationBeyondIntRange()
    {
        // Act
        var result = OtelHostExtensions.Milliseconds("P25D", "interval");

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain($"{int.MaxValue}ms");
    }

    [Fact]
    public void Apply_WritesOnlyPrevalidatedSettingsOntoTheExporter()
    {
        // Arrange
        var settings = Preflighted(Enabled("https://collector:4318", "PT5S"), Env.None);
        var target = new OtlpExporterOptions();

        // Act
        OtelHostExtensions.Apply(target, settings);

        // Assert
        target.Endpoint.Should().Be(new Uri("https://collector:4318"));
        target.Protocol.Should().Be(OtlpExportProtocol.HttpProtobuf);
        target.TimeoutMilliseconds.Should().Be(5000);
    }

    [Fact]
    public void Apply_WritesTheHeadersWhenTheBlockCarriesThem()
    {
        // Arrange
        var configured = Enabled();
        configured.Headers = new Dictionary<string, string>(StringComparer.Ordinal) { ["x-tenant"] = "acme" };
        var settings = Preflighted(configured, Env.None);
        var target = new OtlpExporterOptions();

        // Act
        OtelHostExtensions.Apply(target, settings);

        // Assert
        target.Headers.Should().Contain("x-tenant=acme");
    }

    [Fact]
    public void Apply_LeavesTheEndpointAndHeadersAtTheSdkDefaultWhenThePreflightYieldedNone()
    {
        // Arrange
        var settings = Preflighted(
            Enabled(endpoint: ""),
            Env.Of((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318")));
        var target = new OtlpExporterOptions();
        var headers = target.Headers;

        // Act
        OtelHostExtensions.Apply(target, settings);

        // Assert
        settings.Endpoint.Should().BeNone();
        target.Endpoint.Host.Should().NotBe("ops");
        target.Headers.Should().Be(headers);
    }

    [Fact]
    public void Apply_RejectsANullTarget()
    {
        // Arrange
        var settings = Preflighted(Enabled(), Env.None);

        // Act
        var act = () => OtelHostExtensions.Apply(null!, settings);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Preflight_RejectsABlankEndpointWhenNoEnvironmentOverrideExists()
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(endpoint: "   "), Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("needs an endpoint");
    }

    [Theory]
    [InlineData("collector:4318")]
    [InlineData("ftp://collector:4318")]
    [InlineData("/relative/path")]
    public void Preflight_RejectsAnEndpointThatIsNotAnAbsoluteHttpUri(string endpoint)
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(endpoint), Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("absolute http or https URI");
    }

    [Theory]
    [InlineData("http://collector:4317")]
    [InlineData("http://collector")]
    [InlineData("https://collector")]
    [InlineData("http://collector:8080")]
    public void Preflight_RejectsAnyPortOtherThanTheExplicitFleetPort(string endpoint)
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(endpoint), Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain(":4318");
    }

    [Fact]
    public void Preflight_AcceptsAnHttpsFleetPortEndpoint()
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled("https://collector:4318"), Env.None);

        // Assert
        result.Should().BeOk().Which.Endpoint.Should().BeSome().Which.Scheme.Should().Be("https");
    }

    [Fact]
    public void Preflight_YieldsNoHeadersWhenTheBlockCarriesNone()
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(), Env.None);

        // Assert
        result.Should().BeOk().Which.Headers.Should().BeNone();
    }

    [Fact]
    public void Preflight_RejectsABadTimeout()
    {
        // Act
        var result = OtelHostExtensions.Preflight(Enabled(timeout: "10s"), Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("timeout");
    }

    [Fact]
    public void Preflight_RejectsANonFleetProtocol()
    {
        // Arrange
        var otlp = new OtlpExporterOption { Enabled = true, Endpoint = "http://c:4318", Protocol = "grpc" };

        // Act
        var result = OtelHostExtensions.Preflight(otlp, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("pinned");
    }

    [Fact]
    public void Preflight_RejectsANullBlock()
    {
        // Act
        var act = () => OtelHostExtensions.Preflight(null!, Env.None);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Preflight_RejectsANullEnvironment()
    {
        // Act
        var act = () => OtelHostExtensions.Preflight(new OtlpExporterOption(), null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Preflight_TreatsNullHeadersAsNoHeaders()
    {
        // Arrange
        var otlp = Enabled();
        otlp.Headers = null!;

        // Act
        var result = OtelHostExtensions.Preflight(otlp, Env.None);

        // Assert
        result.Should().BeOk().Which.Headers.Should().BeNone();
    }

    [Theory]
    [InlineData("timeout", "absent")]
    [InlineData("protocol", "pinned")]
    [InlineData("endpoint", "needs an endpoint")]
    public void Preflight_TreatsANullBlockFieldAsARejectionRatherThanThrowing(string field, string message)
    {
        // Arrange
        var otlp = Enabled();
        switch (field)
        {
            case "timeout":
                otlp.Timeout = null!;
                break;
            case "protocol":
                otlp.Protocol = null!;
                break;
            default:
                otlp.Endpoint = null!;
                break;
        }

        // Act
        var result = OtelHostExtensions.Preflight(otlp, Env.None);

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain(message);
    }

    [Fact]
    public void Duration_TreatsAnAbsentValueAsARejection()
    {
        // Act
        var result = OtelHostExtensions.Duration(null, "interval");

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("absent");
    }

    [Fact]
    public void Apply_RejectsNullSettings()
    {
        // Arrange
        var target = new OtlpExporterOptions();

        // Act
        var act = () => OtelHostExtensions.Apply(target, null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void OtlpSettings_CanOnlyBeProducedByPreflight()
    {
        // Act
        var type = typeof(OtelHostExtensions.OtlpSettings);

        // Assert
        type.GetConstructors().Should().BeEmpty("no public constructor may exist");
        type.GetProperties().Should().AllSatisfy(property =>
            property.CanWrite.Should().BeFalse($"'{property.Name}' must be get-only"));
    }

    [Theory]
    [InlineData("PT60S", 60)]
    [InlineData("PT1M", 60)]
    [InlineData("PT0.5S", 0.5)]
    public void Duration_ParsesAnIso8601Duration(string wire, double seconds)
    {
        // Act
        var result = OtelHostExtensions.Duration(wire, "interval");

        // Assert
        result.Should().BeOk().Which.TotalSeconds.Should().Be(seconds);
    }

    [Theory]
    [InlineData("60s")]
    [InlineData("P1M")]
    [InlineData("")]
    public void Duration_RejectsAnythingElse(string wire)
    {
        // Act
        var result = OtelHostExtensions.Duration(wire, "interval");

        // Assert
        result.Should().BeErr().Which.Message.Should().Contain("interval");
    }

    [Fact]
    public void Duration_ReportsTheOffendingValueAndTheConfigOperation()
    {
        // Act
        var result = OtelHostExtensions.Duration("nope", "metrics interval");

        // Assert
        var error = result.Should().BeErr().Which;
        error.Operation.Should().Be("config");
        error.Message.Should().Contain("nope");
    }
}
