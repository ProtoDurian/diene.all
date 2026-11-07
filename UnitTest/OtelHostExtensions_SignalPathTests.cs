using OpenTelemetry.Exporter;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelHostExtensions_SignalPathTests
{
    private static readonly Dictionary<string, string?> NoEnvironment = new(StringComparer.Ordinal);

    private static OtelHostExtensions.OtlpSettings Settings(string endpoint, IReadOnlyDictionary<string, string?> environment) =>
        OtelHostExtensions
            .Preflight(new OtlpExporterOption { Enabled = true, Endpoint = endpoint }, environment)
            .Should().BeOk().Which;

    [Theory]
    [InlineData(OtlpSignal.Traces, "https://collector:4318/v1/traces")]
    [InlineData(OtlpSignal.Metrics, "https://collector:4318/v1/metrics")]
    [InlineData(OtlpSignal.Logs, "https://collector:4318/v1/logs")]
    public void Apply_AppendsTheSignalPathToABlockEndpoint(OtlpSignal signal, string expected)
    {
        // Arrange
        var settings = Settings("https://collector:4318", NoEnvironment);
        var target = new OtlpExporterOptions();

        // Act
        OtelHostExtensions.Apply(target, settings, signal);

        // Assert
        target.Endpoint.Should().Be(new Uri(expected));
    }

    [Fact]
    public void Apply_KeepsABasePathAndDropsItsTrailingSlash()
    {
        // Arrange
        var settings = Settings("https://collector:4318/otlp/", NoEnvironment);
        var target = new OtlpExporterOptions();

        // Act
        OtelHostExtensions.Apply(target, settings, OtlpSignal.Metrics);

        // Assert
        target.Endpoint.Should().Be(new Uri("https://collector:4318/otlp/v1/metrics"));
    }

    [Fact]
    public void Apply_LeavesTheEndpointToTheSdkWhenTheEnvironmentOwnsIt()
    {
        // Arrange
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            [OtelEnvironment.OtlpEndpointVariable] = "http://ops:4318",
        };
        var settings = Settings("", environment);
        var target = new OtlpExporterOptions();
        var unsignalled = new OtlpExporterOptions();
        OtelHostExtensions.Apply(unsignalled, settings);

        // Act
        OtelHostExtensions.Apply(target, settings, OtlpSignal.Traces);

        // Assert
        target.Endpoint.Should().Be(unsignalled.Endpoint);
    }

    [Fact]
    public void Apply_StillPinsHttpProtobufAndTheTimeout()
    {
        // Arrange
        var settings = Settings("https://collector:4318", NoEnvironment);
        var target = new OtlpExporterOptions();

        // Act
        OtelHostExtensions.Apply(target, settings, OtlpSignal.Logs);

        // Assert
        target.Protocol.Should().Be(OtlpExportProtocol.HttpProtobuf);
        target.TimeoutMilliseconds.Should().Be(10_000);
    }

    [Fact]
    public void Apply_RejectsAnUnknownSignalBeforeTouchingTheTarget()
    {
        // Arrange
        var settings = Settings("https://collector:4318", NoEnvironment);
        var target = new OtlpExporterOptions();
        var untouched = target.Endpoint;

        // Act
        var act = () => OtelHostExtensions.Apply(target, settings, (OtlpSignal)99);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
        target.Endpoint.Should().Be(untouched);
    }
}
