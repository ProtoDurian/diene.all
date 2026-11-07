namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelEnvironmentTests
{
    private static ExporterOption BothOn => new()
    {
        Console = new ConsoleExporterOption { Enabled = true },
        Otlp = new OtlpExporterOption { Enabled = true },
    };

    [Fact]
    public void HasValue_RejectsAnAbsentVariable()
    {
        // Act
        var has = OtelEnvironment.HasValue(Env.None, "OTEL_LOGS_EXPORTER");

        // Assert
        has.Should().BeFalse();
    }

    [Theory]
    [InlineData("   ", false)]
    [InlineData(null, false)]
    [InlineData("otlp", true)]
    public void HasValue_OnlyAcceptsANonBlankValue(string? value, bool expected)
    {
        // Arrange
        var environment = Env.Of(("OTEL_LOGS_EXPORTER", value));

        // Act
        var has = OtelEnvironment.HasValue(environment, "OTEL_LOGS_EXPORTER");

        // Assert
        has.Should().Be(expected);
    }

    [Fact]
    public void HasValue_RejectsANullEnvironment()
    {
        // Act
        var act = () => OtelEnvironment.HasValue(null!, "OTEL_SDK_DISABLED");

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [InlineData("true", true)]
    [InlineData("TRUE", true)]
    [InlineData("  true  ", true)]
    [InlineData("false", false)]
    [InlineData("1", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsSdkDisabled_OnlyHonoursTrue(string? value, bool expected)
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.SdkDisabledVariable, value));

        // Act
        var disabled = OtelEnvironment.IsSdkDisabled(environment);

        // Assert
        disabled.Should().Be(expected);
    }

    [Fact]
    public void IsSdkDisabled_IsFalseWhenUnset()
    {
        // Act
        var disabled = OtelEnvironment.IsSdkDisabled(Env.None);

        // Assert
        disabled.Should().BeFalse();
    }

    [Fact]
    public void IsSdkDisabled_RejectsANullEnvironment()
    {
        // Act
        var act = () => OtelEnvironment.IsSdkDisabled(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Exporters_DefersToTheBlockWhenTheOverrideIsUnset()
    {
        // Act
        var selection = OtelEnvironment.Exporters(BothOn, OtelEnvironment.LogsExporterVariable, Env.None);

        // Assert
        selection.Should().Be(new ExporterSelection(true, true));
    }

    [Fact]
    public void Exporters_DefersToTheBlockWhenTheOverrideIsBlank()
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.LogsExporterVariable, " "));

        // Act
        var selection = OtelEnvironment.Exporters(BothOn, OtelEnvironment.LogsExporterVariable, environment);

        // Assert
        selection.Should().Be(new ExporterSelection(true, true));
    }

    [Fact]
    public void Exporters_DefersToABlockWithEveryExporterOff()
    {
        // Act
        var selection = OtelEnvironment.Exporters(
            new ExporterOption(),
            OtelEnvironment.LogsExporterVariable,
            Env.None);

        // Assert
        selection.Should().Be(new ExporterSelection(false, false));
    }

    [Theory]
    [InlineData("none", false, false)]
    [InlineData("console,otlp", true, true)]
    [InlineData("console", true, false)]
    [InlineData("otlp", false, true)]
    [InlineData("OTLP", false, true)]
    [InlineData(" console , otlp ", true, true)]
    [InlineData("jaeger", false, false)]
    [InlineData("otlp,none", false, false)]
    public void Exporters_TreatsTheOverrideAsSetMembership(string value, bool console, bool otlp)
    {
        // Arrange
        var environment = Env.Of((OtelEnvironment.TracesExporterVariable, value));

        // Act
        var selection = OtelEnvironment.Exporters(BothOn, OtelEnvironment.TracesExporterVariable, environment);

        // Assert
        selection.Should().Be(new ExporterSelection(console, otlp));
    }

    [Fact]
    public void Exporters_RejectsANullBlock()
    {
        // Act
        var act = () => OtelEnvironment.Exporters(null!, "OTEL_LOGS_EXPORTER", Env.None);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Exporters_RejectsANullEnvironment()
    {
        // Act
        var act = () => OtelEnvironment.Exporters(BothOn, "OTEL_LOGS_EXPORTER", null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void Process_ReadsTheHostEnvironment()
    {
        // Act
        var environment = OtelEnvironment.Process();

        // Assert
        environment.Should().NotBeNull();
        environment.Keys.Should().OnlyHaveUniqueItems();
    }

    [Fact]
    public void VariableNames_AreTheStandardOtelSpellings()
    {
        // Act
        string[] names =
        [
            OtelEnvironment.LogsExporterVariable,
            OtelEnvironment.MetricsExporterVariable,
            OtelEnvironment.TracesExporterVariable,
            OtelEnvironment.OtlpEndpointVariable,
            OtelEnvironment.ResourceAttributesVariable,
            OtelEnvironment.ServiceNameVariable,
            OtelEnvironment.TracesSamplerVariable,
            OtelEnvironment.SdkDisabledVariable,
        ];

        // Assert
        names.Should().Equal(
            "OTEL_LOGS_EXPORTER",
            "OTEL_METRICS_EXPORTER",
            "OTEL_TRACES_EXPORTER",
            "OTEL_EXPORTER_OTLP_ENDPOINT",
            "OTEL_RESOURCE_ATTRIBUTES",
            "OTEL_SERVICE_NAME",
            "OTEL_TRACES_SAMPLER",
            "OTEL_SDK_DISABLED");
    }
}
