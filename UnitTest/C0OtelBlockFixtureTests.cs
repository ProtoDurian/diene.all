using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

public class C0OtelBlockFixtureTests
{
    private static JsonElement Fixture { get; } = JsonDocument
        .Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "otel-block-v1.json")))
        .RootElement;

    private static IReadOnlyDictionary<string, string> Entries(string property) =>
        Fixture.GetProperty(property).EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString()!);

    private static string[] PinnedSamplerTypes() =>
        [.. Fixture.GetProperty("samplerTypes").EnumerateArray().Select(t => t.GetString()!)];

    [Fact]
    public void Section_MatchesTheOptionKey()
    {
        // Act
        var section = Fixture.GetProperty("section").GetString();

        // Assert
        section.Should().Be(OtelOption.Key);
    }

    [Fact]
    public void EveryPinnedPathBindsToTheOptionsGraph()
    {
        // Arrange
        var values = Entries("paths").Values.ToDictionary(
            path => path,
            path => path.EndsWith("Ratio", StringComparison.Ordinal) ? "0.5"
                : path.EndsWith("Interval", StringComparison.Ordinal) ? "PT30S"
                : path.EndsWith("Timeout", StringComparison.Ordinal) ? "PT5S"
                : path.EndsWith("Endpoint", StringComparison.Ordinal) ? "http://collector:4318"
                : path.EndsWith("Protocol", StringComparison.Ordinal) ? "http/protobuf"
                : path.EndsWith("Type", StringComparison.Ordinal) ? "always_on"
                : "true",
            StringComparer.Ordinal);
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(values.Select(entry => new KeyValuePair<string, string?>(entry.Key, entry.Value)))
            .Build();

        // Act
        var option = configuration.GetSection(OtelOption.Key).Get<OtelOption>();

        // Assert
        option.Should().NotBeNull();
        option!.Logs.Exporter.Otlp.Endpoint.Should().Be("http://collector:4318");
        option.Logs.Exporter.Otlp.Timeout.Should().Be("PT5S");
        option.Metrics.Interval.Should().Be("PT30S");
        option.Traces.Sampler.Type.Should().Be("always_on");
        option.Traces.Sampler.Ratio.Should().Be(0.5);
        option.Traces.Exporter.Otlp.Enabled.Should().BeTrue();
    }

    [Fact]
    public void EveryPinnedEnvNameIsThePrefixedDoubleUnderscoreSpellingOfItsPath()
    {
        // Arrange
        var prefix = Fixture.GetProperty("envPrefix").GetString()!;
        var paths = Entries("paths");
        var envNames = Entries("envNames");

        // Act
        var expected = envNames.Keys.ToDictionary(
            key => key,
            key => paths.TryGetValue(key, out var path)
                ? prefix + path.Replace(':', '_').Replace("_", "__", StringComparison.Ordinal).ToUpperInvariant()
                : null,
            StringComparer.Ordinal);

        // Assert
        paths.Keys.Should().Contain(envNames.Keys);
        envNames.Should().BeEquivalentTo(expected);
    }

    [Fact]
    public void PinnedDefaultsMatchTheShippedOptionDefaults()
    {
        // Arrange
        var defaults = Fixture.GetProperty("defaults");

        // Act
        var option = new OtelOption();

        // Assert
        option.Logs.Enabled.Should().Be(defaults.GetProperty("signalEnabled").GetBoolean());
        option.Logs.Exporter.Console.Enabled.Should().Be(defaults.GetProperty("consoleEnabled").GetBoolean());
        option.Logs.Exporter.Otlp.Enabled.Should().Be(defaults.GetProperty("otlpEnabled").GetBoolean());
        option.Logs.Exporter.Otlp.Endpoint.Should().Be(defaults.GetProperty("otlpEndpoint").GetString());
        option.Logs.Exporter.Otlp.Protocol.Should().Be(defaults.GetProperty("otlpProtocol").GetString());
        option.Logs.Exporter.Otlp.Timeout.Should().Be(defaults.GetProperty("otlpTimeout").GetString());
        option.Metrics.Interval.Should().Be(defaults.GetProperty("metricsInterval").GetString());
        option.Traces.Sampler.Type.Should().Be(defaults.GetProperty("samplerType").GetString());
        option.Traces.Sampler.Ratio.Should().Be(defaults.GetProperty("samplerRatio").GetDouble());
    }

    [Fact]
    public void PinnedSamplerTypesAreExactlyTheOnesTheEngineNames()
    {
        // Act
        var types = PinnedSamplerTypes();

        // Assert
        types.Should().BeEquivalentTo([
            OtelSampler.ParentBasedTraceIdRatio,
            OtelSampler.AlwaysOn,
            OtelSampler.AlwaysOff,
        ]);
    }

    [Fact]
    public void EveryPinnedSamplerTypeIsMappedByTheEngine()
    {
        // Arrange
        var types = PinnedSamplerTypes();

        // Act
        var results = types.Select(type => OtelSampler.Create(new SamplerOption { Type = type }, Env.None)).ToList();

        // Assert
        results.Should().HaveCount(3);
        results.Should().AllSatisfy(result => result.Should().BeOk());
    }

    [Fact]
    public void PinnedResourceKeysAreExactlyTheMappedKeys()
    {
        // Arrange
        var mapped = AtomiResource.Map(new AppIdentity("l", "p", "s", "m", "v")).Keys;

        // Act
        var pinned = Fixture.GetProperty("resourceKeys").EnumerateArray().Select(key => key.GetString());

        // Assert
        pinned.Should().BeEquivalentTo(mapped);
    }

    [Fact]
    public void PinnedProtocolMatchesTheHostExtensionConstant()
    {
        // Act
        var protocol = Fixture.GetProperty("defaults").GetProperty("otlpProtocol").GetString();

        // Assert
        protocol.Should().Be(OtelHostExtensions.OtlpProtocol);
    }
}
