using System.Text.Json;

namespace AtomiCloud.DotnetBase.UnitTest;

public class C0FixtureTests
{
    private static JsonElement Fixture { get; } = JsonDocument
        .Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "wire-v1.json")))
        .RootElement;

    private static string Value(string name) => Fixture.GetProperty(name).GetString()!;

    private static Dictionary<string, string> Pairs(string name) => Fixture.GetProperty(name)
        .EnumerateObject()
        .ToDictionary(entry => entry.Name, entry => entry.Value.GetString()!, StringComparer.Ordinal);

    [Fact]
    public void It_should_pin_the_fixture_contract_version()
    {
        // Act
        var version = Fixture.GetProperty("version").GetInt32();

        // Assert
        version.Should().Be(1);
    }

    [Fact]
    public void It_should_mark_the_fixture_as_a_local_regression_only_contract()
    {
        // Act
        var status = Fixture.GetProperty("status").GetString();

        // Assert
        status.Should().Be("local-regression-only");
    }

    [Theory]
    [InlineData("date")]
    [InlineData("time")]
    [InlineData("instant")]
    [InlineData("instantWithFraction")]
    [InlineData("duration")]
    [InlineData("durationWithDays")]
    [InlineData("timeZone")]
    [InlineData("decimal")]
    [InlineData("int64")]
    public void It_should_round_trip_every_pinned_wire_value(string name)
    {
        // Arrange
        var wire = Value(name);

        // Act
        var rendered = name switch
        {
            "date" => Wire.Format(Wire.ParseDate(wire).Should().BeOk().Which),
            "time" => Wire.Format(Wire.ParseTime(wire).Should().BeOk().Which),
            "instant" or "instantWithFraction" => Wire.Format(Wire.ParseInstant(wire).Should().BeOk().Which),
            "duration" or "durationWithDays" => Wire.Format(Wire.ParseDuration(wire).Should().BeOk().Which),
            "timeZone" => Wire.Format(Wire.ParseTimeZone(wire).Should().BeOk().Which),
            "decimal" => Wire.Format(Wire.ParseDecimal(wire).Should().BeOk().Which),
            _ => Wire.Format(Wire.ParseInt64(wire).Should().BeOk().Which),
        };

        // Assert
        rendered.Should().Be(wire);
    }

    [Fact]
    public void It_should_normalize_the_pinned_offset_instant_onto_the_pinned_utc_instant()
    {
        // Arrange
        var wire = Value("instantWithOffset");

        // Act
        var rendered = Wire.Format(Wire.ParseInstant(wire).Should().BeOk().Which);

        // Assert
        rendered.Should().Be(Value("instant"));
    }

    [Fact]
    public void It_should_reproduce_the_pinned_cross_language_slugs()
    {
        // Arrange
        var expected = Pairs("slugs");

        // Act
        var actual = expected.Keys.ToDictionary(input => input, Slug.Slugify, StringComparer.Ordinal);

        // Assert
        actual.Should().Equal(expected);
    }

    [Fact]
    public void It_should_reproduce_the_pinned_canonical_keys()
    {
        // Arrange
        var expected = Pairs("keys");

        // Act
        var actual = expected.Keys.ToDictionary(key => key, KeyNormalizer.Canonical, StringComparer.Ordinal);

        // Assert
        actual.Should().Equal(expected);
    }
}
