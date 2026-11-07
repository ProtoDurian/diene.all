using System.ComponentModel.DataAnnotations;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelOptionTests
{
    private static IReadOnlyList<ValidationResult> Validate(object instance)
    {
        var results = new List<ValidationResult>();
        Validator.TryValidateObject(instance, new ValidationContext(instance), results, validateAllProperties: true);
        return results;
    }

    private static OtelOption Bind(params (string Path, string Value)[] entries) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(entries.Select(entry =>
                new KeyValuePair<string, string?>(entry.Path, entry.Value)))
            .Build()
            .GetSection(OtelOption.Key)
            .Get<OtelOption>() ?? new OtelOption();

    [Fact]
    public void Key_IsTheCanonicalSectionName()
    {
        // Act
        var key = OtelOption.Key;

        // Assert
        key.Should().Be("Otel");
    }

    [Fact]
    public void Defaults_AreSignalsOnAndExportersOff()
    {
        // Act
        var option = new OtelOption();

        // Assert
        option.Logs.Enabled.Should().BeTrue();
        option.Metrics.Enabled.Should().BeTrue();
        option.Traces.Enabled.Should().BeTrue();
        new[] { option.Logs.Exporter, option.Metrics.Exporter, option.Traces.Exporter }.Should().AllSatisfy(exporter =>
        {
            exporter.Console.Enabled.Should().BeFalse();
            exporter.Otlp.Enabled.Should().BeFalse();
            exporter.Otlp.Endpoint.Should().BeEmpty();
            exporter.Otlp.Protocol.Should().Be("http/protobuf");
            exporter.Otlp.Timeout.Should().Be("PT10S");
            exporter.Otlp.Headers.Should().BeEmpty();
        });
        option.Metrics.Interval.Should().Be("PT60S");
        option.Traces.Sampler.Type.Should().Be("parentbased_traceidratio");
        option.Traces.Sampler.Ratio.Should().Be(1.0);
    }

    [Fact]
    public void Signals_AreIndependentlyAssignable()
    {
        // Act
        var option = new OtelOption
        {
            Logs = new LogsOption { Enabled = false },
            Metrics = new MetricsOption { Enabled = false, Interval = "PT30S" },
            Traces = new TracesOption { Enabled = false, Sampler = new SamplerOption { Type = "always_off" } },
        };

        // Assert
        option.Logs.Enabled.Should().BeFalse();
        option.Metrics.Interval.Should().Be("PT30S");
        option.Traces.Sampler.Type.Should().Be("always_off");
    }

    [Fact]
    public void Exporter_IsIndependentlyAssignable()
    {
        // Arrange
        var otlp = new OtlpExporterOption
        {
            Enabled = true,
            Endpoint = "http://collector:4318",
            Protocol = "http/protobuf",
            Timeout = "PT5S",
            Headers = new Dictionary<string, string>(StringComparer.Ordinal) { ["x-tenant"] = "acme" },
        };

        // Act
        var option = new SignalOption
        {
            Enabled = true,
            Exporter = new ExporterOption
            {
                Console = new ConsoleExporterOption { Enabled = true },
                Otlp = otlp,
            },
        };

        // Assert
        option.Exporter.Console.Enabled.Should().BeTrue();
        option.Exporter.Otlp.Should().BeSameAs(otlp);
        otlp.Headers.Should().ContainKey("x-tenant");
    }

    [Fact]
    public void Binding_ReadsTheCanonicalBlockPaths()
    {
        // Act
        var option = Bind(
            ("Otel:Logs:Enabled", "false"),
            ("Otel:Logs:Exporter:Otlp:Enabled", "true"),
            ("Otel:Logs:Exporter:Otlp:Endpoint", "http://collector:4318"),
            ("Otel:Logs:Exporter:Otlp:Headers:x-tenant", "acme"),
            ("Otel:Metrics:Interval", "PT30S"),
            ("Otel:Metrics:Exporter:Console:Enabled", "true"),
            ("Otel:Traces:Sampler:Type", "always_on"),
            ("Otel:Traces:Sampler:Ratio", "0.25"));

        // Assert
        option.Logs.Enabled.Should().BeFalse();
        option.Logs.Exporter.Otlp.Enabled.Should().BeTrue();
        option.Logs.Exporter.Otlp.Endpoint.Should().Be("http://collector:4318");
        option.Logs.Exporter.Otlp.Headers["x-tenant"].Should().Be("acme");
        option.Metrics.Interval.Should().Be("PT30S");
        option.Metrics.Exporter.Console.Enabled.Should().BeTrue();
        option.Traces.Sampler.Type.Should().Be("always_on");
        option.Traces.Sampler.Ratio.Should().Be(0.25);
    }

    [Fact]
    public void Binding_AnEmptyRootYieldsTheShippedDefaults()
    {
        // Act
        var option = Bind(("Unrelated:Key", "value"));

        // Assert
        option.Metrics.Interval.Should().Be("PT60S");
    }

    [Fact]
    public void Binding_TheEnvironmentSpellingOfABlockPathIsDoubleUnderscore()
    {
        // Arrange
        const string variable = "ATOMI_OTEL__LOGS__EXPORTER__OTLP__ENABLED";

        // Act
        var path = variable
            .Replace("ATOMI_", string.Empty, StringComparison.Ordinal)
            .Replace("__", ":", StringComparison.Ordinal);

        // Assert
        path.Should().Be("OTEL:LOGS:EXPORTER:OTLP:ENABLED");
    }

    [Fact]
    public void Binding_AnEnvironmentWithoutThePrefixedBlockBindsNoBlock()
    {
        // Arrange
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection([new("ATOMI_", null)])
            .AddEnvironmentVariables("ATOMI_")
            .Build();

        // Act
        var option = configuration.GetSection(OtelOption.Key).Get<OtelOption>();

        // Assert
        option.Should().BeNull();
    }

    [Theory]
    [InlineData("parentbased_traceidratio")]
    [InlineData("always_on")]
    [InlineData("always_off")]
    public void Sampler_AcceptsTheThreeCanonicalTypes(string type)
    {
        // Act
        var errors = Validate(new SamplerOption { Type = type });

        // Assert
        errors.Should().BeEmpty();
    }

    [Theory]
    [InlineData("traceidratio")]
    [InlineData("ALWAYS_ON")]
    [InlineData("")]
    public void Sampler_RejectsAnyOtherType(string type)
    {
        // Act
        var errors = Validate(new SamplerOption { Type = type });

        // Assert
        errors.Should().NotBeEmpty();
    }

    [Theory]
    [InlineData(0.0)]
    [InlineData(0.5)]
    [InlineData(1.0)]
    public void Sampler_AcceptsARatioInsideTheUnitInterval(double ratio)
    {
        // Act
        var errors = Validate(new SamplerOption { Ratio = ratio });

        // Assert
        errors.Should().BeEmpty();
    }

    [Theory]
    [InlineData(-0.1)]
    [InlineData(1.1)]
    public void Sampler_RejectsARatioOutsideTheUnitInterval(double ratio)
    {
        // Act
        var errors = Validate(new SamplerOption { Ratio = ratio });

        // Assert
        errors.Should().NotBeEmpty();
    }

    [Fact]
    public void Otlp_AcceptsTheFleetProtocol()
    {
        // Act
        var errors = Validate(new OtlpExporterOption { Protocol = "http/protobuf" });

        // Assert
        errors.Should().BeEmpty();
    }

    [Theory]
    [InlineData("grpc")]
    [InlineData("")]
    public void Otlp_RejectsAnyOtherProtocol(string protocol)
    {
        // Act
        var errors = Validate(new OtlpExporterOption { Protocol = protocol });

        // Assert
        errors.Should().NotBeEmpty();
    }

    [Fact]
    public void Otlp_RequiresATimeout()
    {
        // Act
        var errors = Validate(new OtlpExporterOption { Timeout = null! });

        // Assert
        errors.Should().NotBeEmpty();
    }

    [Fact]
    public void Metrics_RequiresAnInterval()
    {
        // Act
        var errors = Validate(new MetricsOption { Interval = null! });

        // Assert
        errors.Should().NotBeEmpty();
    }
}
