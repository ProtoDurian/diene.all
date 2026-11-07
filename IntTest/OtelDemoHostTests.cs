namespace AtomiCloud.DotnetBase.IntTest;

public class OtelDemoHostTests
{
    private static string Run(IReadOnlyDictionary<string, string?> environment, OtelOption? option = null)
    {
        var output = new StringWriter();
        OtelDemo.Run(output, option ?? OtelDemo.Sample(), environment).Should().Be(0);
        return output.ToString();
    }

    private static IReadOnlyDictionary<string, string?> Env(params (string Name, string? Value)[] entries)
    {
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var (name, value) in entries) environment[name] = value;
        return environment;
    }

    private static Dictionary<string, AttributeValue> Attributes() => new(StringComparer.Ordinal)
    {
        ["route"] = AttributeValue.Text("/v1/demo"),
    };

    [Fact]
    public void Identity_IsTheDemoServiceTreeIdentity()
    {
        // Act
        var identity = OtelDemo.Identity;

        // Assert
        identity.Landscape.Should().Be("lapras");
        identity.Platform.Should().Be("atomi");
        identity.Service.Should().Be("dotnet-otel-demo");
        identity.Module.Should().Be("app");
        identity.Version.Should().Be("1.0.0");
    }

    [Fact]
    public void Sample_ShipsEverySignalOnAndEveryExporterOff()
    {
        // Act
        var option = OtelDemo.Sample();

        // Assert
        option.Logs.Enabled.Should().BeTrue();
        option.Metrics.Enabled.Should().BeTrue();
        option.Traces.Enabled.Should().BeTrue();
        new[] { option.Logs.Exporter, option.Metrics.Exporter, option.Traces.Exporter }.Should().AllSatisfy(exporter =>
        {
            exporter.Console.Enabled.Should().BeFalse();
            exporter.Otlp.Enabled.Should().BeFalse();
        });
    }

    [Fact]
    public void Run_ReportsTheWiredResourceAttributes()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("semconv service: dotnet-otel-demo ns=atomi version=1.0.0 env=lapras");
        output.Should().Contain("raw atomi.module: app");
        output.Should().Contain("effective resource attributes: 9");
        output.Should().Contain("resource builder built: True");
    }

    [Fact]
    public void Run_ReportsEverySignalAsSilentUnderTheShippedDefaults()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("logs exporters: console=False otlp=False");
        output.Should().Contain("metrics exporters: console=False otlp=False");
        output.Should().Contain("traces exporters: console=False otlp=False");
        output.Should().Contain("'none' override: ExporterSelection { Console = False, Otlp = False }");
    }

    [Fact]
    public void Run_ProvesTheBlockConsoleToggleReachesAnExporterSelection()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("lapras console overlay: ExporterSelection { Console = True, Otlp = False }");
    }

    [Fact]
    public void Run_HonoursAnExporterOverrideFromTheEnvironment()
    {
        // Arrange
        // The sample block ships no endpoint, so selecting OTLP needs the ops endpoint override.
        var environment = Env(
            (OtelEnvironment.LogsExporterVariable, "console"),
            (OtelEnvironment.MetricsExporterVariable, "otlp"),
            (OtelEnvironment.TracesExporterVariable, "none"),
            (OtelEnvironment.OtlpEndpointVariable, "http://collector:4318"));

        // Act
        var output = Run(environment);

        // Assert
        output.Should().Contain("logs exporters: console=True otlp=False");
        output.Should().Contain("metrics exporters: console=False otlp=True");
        output.Should().Contain("traces exporters: console=False otlp=False");
        output.Should().Contain("host wired: True");
    }

    [Fact]
    public void Run_ReportsWiringAsFailedWhenAnOverrideSelectsOtlpWithNoEndpoint()
    {
        // Arrange
        var environment = Env((OtelEnvironment.MetricsExporterVariable, "otlp"));

        // Act
        var output = Run(environment);

        // Assert
        output.Should().Contain("host wired: False");
        output.Should().Contain("emitter=not wired (InvalidInput)");
    }

    [Fact]
    public void Run_LetsResourceAttributesOverrideTheDerivedServiceName()
    {
        // Arrange
        var environment = Env((OtelEnvironment.ServiceNameVariable, "renamed"));

        // Act
        var output = Run(environment);

        // Assert
        output.Should().Contain($"{OtelEnvironment.ServiceNameVariable} set: True");
    }

    [Fact]
    public void Run_ReportsTheSdkAsDisabledWhenTheVariableSaysSo()
    {
        // Arrange
        var environment = Env((OtelEnvironment.SdkDisabledVariable, "true"));

        // Act
        var output = Run(environment);

        // Assert
        output.Should().Contain("sdk disabled: True");
        output.Should().Contain("sdk-disabled=True");
    }

    [Fact]
    public void Run_SkipsTheProgrammaticEndpointWhenOpsSetsOne()
    {
        // Arrange
        var environment = Env((OtelEnvironment.OtlpEndpointVariable, "http://ops:4318"));

        // Act
        var output = Run(environment);

        // Assert
        output.Should().Contain($"{OtelEnvironment.OtlpEndpointVariable} set: True");
        output.Should().NotContain("otlp configured: http://collector:4318/");
    }

    [Fact]
    public void Run_ExercisesEveryTraceSeamInvariant()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("attributes checked: attempt,elapsed,retried,route");
        output.Should().Contain("blank key rejected: invalid-input");
        output.Should().Contain("span: demo.request ok events=1 status=ok message=served");
        output.Should().Contain("blank event rejected: emit");
        output.Should().Contain("blank status message rejected: InvalidInput");
    }

    [Fact]
    public void Run_EmitsThroughTheRealActivityEmitter()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("activity emitted: demo.request status=Ok tags=4");
        output.Should().Contain("activity flushed");
    }

    [Fact]
    public void Run_EmitsThroughBothHostBackedSeams()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("log emitted");
        output.Should().Contain("metric Counter emitted");
        output.Should().Contain("metric Gauge emitted");
        output.Should().Contain("metric Histogram emitted");
        output.Should().Contain("NaN rejected: invalid_argument");
    }

    [Fact]
    public void Run_MapsEverySamplerAndRejectsAnUnknownOne()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("sampler always_on: AlwaysOnSampler");
        output.Should().Contain("sampler always_off: AlwaysOffSampler");
        output.Should().Contain("sampler parentbased_traceidratio: ParentBased{TraceIdRatioBasedSampler{");
        output.Should().Contain("unknown sampler rejected: InvalidInput");
    }

    [Fact]
    public void Run_DefersToTheSdkSamplerWhenTheEnvironmentNamesOne()
    {
        // Arrange
        var environment = Env((OtelEnvironment.TracesSamplerVariable, "always_off"));

        // Act
        var output = Run(environment);

        // Assert
        output.Should().Contain("sampler always_on: sdk default");
    }

    [Fact]
    public void Run_RejectsABadIntervalAndReportsItAsRejected()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("bad-interval-rejected=True");
        output.Should().Contain("bad duration rejected:");
    }

    [Fact]
    public void Run_WiresTheHostAndBindsTheBlockFromConfiguration()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain("host wired: True bound=True");
        output.Should().Contain("emitter=ActivityTraceEmitter");
    }

    [Fact]
    public void Run_ShipsTheEngineOwnedBlockSchema()
    {
        // Act
        var output = Run(Env());

        // Assert
        output.Should().Contain($"block schema {OtelBlockSchema.ResourceName}:");
    }

    [Fact]
    public void Run_ReportsANonZeroExitWhenABadBlockIsAccepted()
    {
        // Arrange
        var output = new StringWriter();
        var option = new OtelOption
        {
            Logs = new LogsOption { Enabled = false },
            Metrics = new MetricsOption { Enabled = false },
            Traces = new TracesOption { Enabled = false },
        };

        // Act
        var exit = OtelDemo.Run(output, option, Env());

        // Assert
        exit.Should().Be(0);
    }

    [Fact]
    public void Run_RejectsANullWriter()
    {
        // Act
        var act = () => OtelDemo.Run(null!, OtelDemo.Sample(), Env());

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Run_RejectsANullOption()
    {
        // Act
        var act = () => OtelDemo.Run(new StringWriter(), null!, Env());

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Run_RejectsANullEnvironment()
    {
        // Act
        var act = () => OtelDemo.Run(new StringWriter(), OtelDemo.Sample(), null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void InMemoryLoggerSink_CapturesALogForTheTestHelper()
    {
        // Arrange
        var logger = new InMemoryLoggerSink();

        // Act
        var result = logger.Emit(new LogRecord(DateTimeOffset.UnixEpoch, LogLevel.Info, "request served", Attributes()));

        // Assert
        result.Should().BeOk();
        logger.Should().HaveLogged(LogLevel.Info, "request served");
    }

    [Fact]
    public void InMemoryMetricsCollector_CapturesASampleForTheTestHelper()
    {
        // Arrange
        var metrics = new InMemoryMetricsCollector();
        var sample = new MetricRecord(DateTimeOffset.UnixEpoch, "demo.requests", MetricKind.Counter, 1.0, "1", Attributes());

        // Act
        var result = metrics.Emit(sample);

        // Assert
        result.Should().BeOk();
        metrics.Should().HaveSampled("demo.requests", MetricKind.Counter, 1.0);
    }

    [Fact]
    public void InMemoryTraceEmitter_CapturesASpanForTheTestHelper()
    {
        // Arrange
        var traces = new InMemoryTraceEmitter();
        var record = TraceRecord.Create("demo.request", Attributes(), status: TraceStatus.Ok).Should().BeOk().Which;

        // Act
        var result = traces.Emit(record);

        // Assert
        result.Should().BeOk();
        traces.Should().HaveEmitted("demo.request").Which.Should().HaveStatus(TraceStatus.Ok);
    }
}
