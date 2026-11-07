using System.Text.Json;
using System.Text.Json.Nodes;
using Json.Schema;

namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelBlockSchemaValidationTests
{
    private static JsonSchema Schema { get; } = JsonSchema.FromText(OtelBlockSchema.Json);

    private static EvaluationOptions Options { get; } = new() { OutputFormat = OutputFormat.Hierarchical };

    public static JsonObject Canonical() => new()
    {
        ["logs"] = new JsonObject
        {
            ["enabled"] = true,
            ["exporter"] = Exporter(),
        },
        ["metrics"] = new JsonObject
        {
            ["enabled"] = true,
            ["interval"] = "PT60S",
            ["exporter"] = Exporter(),
        },
        ["traces"] = new JsonObject
        {
            ["enabled"] = true,
            ["sampler"] = new JsonObject
            {
                ["type"] = "parentbased_traceidratio",
                ["ratio"] = 1.0,
            },
            ["exporter"] = Exporter(),
        },
    };

    private static JsonObject Exporter() => new()
    {
        ["console"] = new JsonObject { ["enabled"] = false },
        ["otlp"] = new JsonObject
        {
            ["enabled"] = false,
            ["endpoint"] = "",
            ["protocol"] = "http/protobuf",
            ["headers"] = new JsonObject(),
            ["timeout"] = "PT10S",
        },
    };

    private static bool Valid(JsonNode document) =>
        Schema.Evaluate(JsonSerializer.Deserialize<JsonElement>(document), Options).IsValid;

    private static JsonObject ShippedSchema() => JsonNode.Parse(OtelBlockSchema.Json)!.AsObject();

    [Fact]
    public void Schema_AcceptsTheFullCanonicalBlock()
    {
        // Arrange
        var document = Canonical();

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeTrue();
    }

    [Theory]
    [InlineData("""{ "metrics": { "interval": "PT30S" } }""")]
    [InlineData("""{ "traces": { "sampler": { "type": "always_on" } } }""")]
    public void Schema_AcceptsTheSignalSpecificKeysThatCompositionRejected(string json)
    {
        // Arrange
        var document = JsonNode.Parse(json)!;

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeTrue();
    }

    [Fact]
    public void Schema_AcceptsAnEmptyBlockBecauseEveryKeyHasADefault()
    {
        // Act
        var valid = Valid(new JsonObject());

        // Assert
        valid.Should().BeTrue();
    }

    [Theory]
    [InlineData("""{ "logs": { "bogus": true } }""")]
    [InlineData("""{ "profiling": true }""")]
    public void Schema_StillRejectsAnUnknownKey(string json)
    {
        // Arrange
        var document = JsonNode.Parse(json)!;

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Theory]
    [InlineData("""{ "logs": { "interval": "PT60S" } }""")]
    [InlineData("""{ "metrics": { "sampler": { "type": "always_on" } } }""")]
    public void Schema_RejectsASignalSpecificKeyOnTheWrongSignal(string json)
    {
        // Arrange
        var document = JsonNode.Parse(json)!;

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Theory]
    [InlineData("60s")]
    [InlineData("P1M")]
    public void Schema_RejectsANonIso8601Interval(string interval)
    {
        // Arrange
        var document = new JsonObject { ["metrics"] = new JsonObject { ["interval"] = interval } };

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Fact]
    public void Schema_RejectsANonFleetProtocol()
    {
        // Arrange
        var document = new JsonObject
        {
            ["logs"] = new JsonObject
            {
                ["exporter"] = new JsonObject { ["otlp"] = new JsonObject { ["protocol"] = "grpc" } },
            },
        };

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Theory]
    [InlineData("coin_flip")]
    [InlineData("traceidratio")]
    public void Schema_RejectsAnUnsupportedSamplerType(string type)
    {
        // Arrange
        var document = new JsonObject
        {
            ["traces"] = new JsonObject { ["sampler"] = new JsonObject { ["type"] = type } },
        };

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Theory]
    [InlineData(-0.1)]
    [InlineData(1.1)]
    public void Schema_RejectsARatioOutsideTheUnitInterval(double ratio)
    {
        // Arrange
        var document = new JsonObject
        {
            ["traces"] = new JsonObject { ["sampler"] = new JsonObject { ["ratio"] = ratio } },
        };

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Fact]
    public void Schema_RejectsAWrongTypedValue()
    {
        // Arrange
        var document = new JsonObject { ["logs"] = new JsonObject { ["enabled"] = "yes" } };

        // Act
        var valid = Valid(document);

        // Assert
        valid.Should().BeFalse();
    }

    [Theory]
    [InlineData("logs")]
    [InlineData("metrics")]
    [InlineData("traces")]
    public void Schema_DeclaresEverySignalStandaloneRatherThanComposed(string signal)
    {
        // Arrange
        var properties = ShippedSchema()["properties"]!.AsObject();

        // Act
        var declared = properties[signal]!.AsObject();

        // Assert
        declared.Should().NotContainKey("allOf", $"'{signal}' must not compose a base schema");
        declared["additionalProperties"]!.GetValue<bool>().Should().BeFalse();
        declared["properties"]!.AsObject().Should().ContainKeys("enabled", "exporter");
    }

    [Fact]
    public void Schema_DeclaresTheSignalSpecificKeysOnTheirOwnSignalWithNoSharedBase()
    {
        // Act
        var document = ShippedSchema();

        // Assert
        document["properties"]!["metrics"]!["properties"]!.AsObject().Should().ContainKey("interval");
        document["properties"]!["traces"]!["properties"]!.AsObject().Should().ContainKey("sampler");
        document["$defs"]!.AsObject().Should().NotContainKey("signal");
    }

    [Fact]
    public void SchemaDefaults_MatchTheShippedOptionDefaults()
    {
        // Arrange
        var option = new OtelOption();

        // Act
        var document = ShippedSchema();

        // Assert
        document["properties"]!["metrics"]!["properties"]!["interval"]!["default"]!.GetValue<string>()
            .Should().Be(option.Metrics.Interval);
        var sampler = document["$defs"]!["sampler"]!["properties"]!;
        sampler["type"]!["default"]!.GetValue<string>().Should().Be(option.Traces.Sampler.Type);
        sampler["ratio"]!["default"]!.GetValue<double>().Should().Be(option.Traces.Sampler.Ratio);
        var otlp = document["$defs"]!["exporter"]!["properties"]!["otlp"]!["properties"]!;
        otlp["protocol"]!["default"]!.GetValue<string>().Should().Be(option.Logs.Exporter.Otlp.Protocol);
        otlp["timeout"]!["default"]!.GetValue<string>().Should().Be(option.Logs.Exporter.Otlp.Timeout);
        otlp["enabled"]!["default"]!.GetValue<bool>().Should().Be(option.Logs.Exporter.Otlp.Enabled);
    }
}
