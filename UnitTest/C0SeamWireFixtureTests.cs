using System.Text.Json;

namespace AtomiCloud.DotnetBase.UnitTest;

public class C0SeamWireFixtureTests
{
    private static readonly JsonElement Fixture = Load();

    private static JsonElement Load()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "seam-wire-v1.json")));
        return document.RootElement.Clone();
    }

    private static string[] Names(string property) =>
        [.. Fixture.GetProperty(property).EnumerateArray().Select(element => element.GetString()!)];

    [Fact]
    public void It_should_declare_its_version()
    {
        // Act
        var version = Fixture.GetProperty("version").GetInt32();

        // Assert
        version.Should().Be(1);
    }

    [Fact]
    public void It_should_declare_itself_local_regression_only()
    {
        // Act
        var status = Fixture.GetProperty("status").GetString();

        // Assert
        status.Should().Be("local-regression-only");
    }

    [Fact]
    public void It_should_pin_the_seam_wire_names()
    {
        // Arrange
        var names = Names("seams");

        // Act
        var parsed = names.Select(name => SeamWire.ParseSeamKind(name).Should().BeOk().Which).ToArray();

        // Assert
        parsed.Should().Equal(Enum.GetValues<SeamKind>());
    }

    [Fact]
    public void It_should_pin_the_log_level_wire_names()
    {
        // Arrange
        var names = Names("logLevels");

        // Act
        var parsed = names.Select(name => SeamWire.ParseLogLevel(name).Should().BeOk().Which).ToArray();

        // Assert
        parsed.Should().Equal(Enum.GetValues<LogLevel>());
    }

    [Fact]
    public void It_should_pin_the_metric_kind_wire_names()
    {
        // Arrange
        var names = Names("metricKinds");

        // Act
        var parsed = names.Select(name => SeamWire.ParseMetricKind(name).Should().BeOk().Which).ToArray();

        // Assert
        parsed.Should().Equal(Enum.GetValues<MetricKind>());
    }

    [Fact]
    public void It_should_pin_the_entry_type_wire_names()
    {
        // Arrange
        var names = Names("vfsEntryTypes");

        // Act
        var parsed = names.Select(name => SeamWire.ParseVfsEntryType(name).Should().BeOk().Which).ToArray();

        // Assert
        parsed.Should().Equal(Enum.GetValues<VfsEntryType>());
    }

    [Fact]
    public void It_should_pin_the_attribute_kind_wire_names()
    {
        // Arrange
        var names = Names("attributeKinds");

        // Act
        var parsed = names.Select(name => SeamWire.ParseAttributeValueKind(name).Should().BeOk().Which).ToArray();

        // Assert
        parsed.Should().Equal(Enum.GetValues<AttributeValueKind>());
    }

    [Fact]
    public void It_should_round_trip_the_pinned_instant()
    {
        // Arrange
        var wire = Fixture.GetProperty("instant").GetString()!;

        // Act
        var parsed = SeamWire.ParseInstant(wire).Should().BeOk().Which;

        // Assert
        parsed.Offset.Should().Be(TimeSpan.Zero);
        SeamWire.Instant(parsed).Should().Be(wire);
    }

    [Fact]
    public void It_should_round_trip_the_pinned_duration()
    {
        // Arrange
        var wire = Fixture.GetProperty("duration").GetString()!;

        // Act
        var parsed = SeamWire.ParseDuration(wire).Should().BeOk().Which;

        // Assert
        SeamWire.Duration(parsed).Should().Be(wire);
    }

    [Fact]
    public void It_should_resolve_the_pinned_iana_timezone()
    {
        // Arrange
        var id = Fixture.GetProperty("timeZone").GetString()!;

        // Act
        var result = SeamWire.TimeZone(id);

        // Assert
        result.Should().BeOk();
    }

    [Theory]
    [InlineData("text")]
    [InlineData("integer")]
    [InlineData("real")]
    [InlineData("flag")]
    [InlineData("instant")]
    [InlineData("duration")]
    [InlineData("time_zone")]
    public void It_should_round_trip_the_pinned_attribute_payload(string name)
    {
        // Arrange
        var kind = SeamWire.ParseAttributeValueKind(name).Should().BeOk().Which;
        var wire = Fixture.GetProperty("attributes").GetProperty(name).GetString()!;

        // Act
        var value = AttributeValue.FromWire(kind, wire).Should().BeOk().Which;

        // Assert
        value.Kind.Should().Be(kind);
        value.Wire.Should().Be(wire);
    }

    [Fact]
    public void It_should_cover_every_attribute_kind_with_a_pinned_payload()
    {
        // Act
        var names = Fixture.GetProperty("attributes").EnumerateObject().Select(entry => entry.Name).ToArray();

        // Assert
        names.Should().BeEquivalentTo(Enum.GetValues<AttributeValueKind>().Select(SeamWire.Name));
    }
}
