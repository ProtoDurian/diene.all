namespace AtomiCloud.DotnetBase.UnitTest;

public class SeamWireTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_render_instants_as_rfc_3339_utc()
    {
        // Act
        var wire = SeamWire.Instant(Anchor);

        // Assert
        wire.Should().Be("2026-07-25T22:30:00.0000000Z");
    }

    [Fact]
    public void It_should_normalize_an_offset_instant_to_utc()
    {
        // Arrange
        var offset = new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8));

        // Act
        var wire = SeamWire.Instant(offset);

        // Assert
        wire.Should().Be("2026-07-25T22:30:00.0000000Z");
    }

    [Fact]
    public void It_should_publish_the_instant_format()
    {
        // Act
        var format = SeamWire.InstantFormat;

        // Assert
        format.Should().Be("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'");
    }

    [Theory]
    [InlineData("2026-07-25T22:30:00.0000000Z")]
    [InlineData("2026-07-25T22:30:00Z")]
    [InlineData("2026-07-25T22:30:00.5Z")]
    [InlineData("2026-07-26T06:30:00+08:00")]
    public void It_should_parse_conformant_instants_into_utc(string wire)
    {
        // Act
        var result = SeamWire.ParseInstant(wire);

        // Assert
        result.Should().BeOk().Which.Offset.Should().Be(TimeSpan.Zero);
    }

    [Fact]
    public void It_should_round_trip_an_instant()
    {
        // Arrange
        var wire = SeamWire.Instant(Anchor);

        // Act
        var result = SeamWire.ParseInstant(wire);

        // Assert
        result.Should().BeOk(Anchor);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("25/07/2026")]
    [InlineData("2026-07-25 22:30:00")]
    public void It_should_reject_a_non_conformant_instant(string wire)
    {
        // Act
        var result = SeamWire.ParseInstant(wire);

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Theory]
    [InlineData(90, "PT1M30S")]
    [InlineData(0, "PT0S")]
    [InlineData(3600, "PT1H")]
    public void It_should_render_durations_as_iso_8601(int seconds, string expected)
    {
        // Act
        var wire = SeamWire.Duration(TimeSpan.FromSeconds(seconds));

        // Assert
        wire.Should().Be(expected);
    }

    [Fact]
    public void It_should_round_trip_a_duration()
    {
        // Act
        var result = SeamWire.ParseDuration("PT1M30S");

        // Assert
        result.Should().BeOk(TimeSpan.FromSeconds(90));
    }

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("90s")]
    [InlineData("PT99999999999999999999S")]
    [InlineData("P10675200D")]
    [InlineData("P99999999999999999999Y")]
    public void It_should_reject_a_non_conformant_duration(string wire)
    {
        // Act
        var result = SeamWire.ParseDuration(wire);

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_resolve_an_iana_timezone_id()
    {
        // Act
        var result = SeamWire.TimeZone(TimeZoneInfo.Utc.Id);

        // Assert
        result.Should().BeOk();
    }

    [Fact]
    public void It_should_reject_an_unknown_timezone_id()
    {
        // Act
        var result = SeamWire.TimeZone("Mars/Olympus");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "unknown_time_zone");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void It_should_reject_a_blank_timezone_id(string id)
    {
        // Act
        var result = SeamWire.TimeZone(id);

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Theory]
    [InlineData(SeamKind.System, "system")]
    [InlineData(SeamKind.Vfs, "vfs")]
    [InlineData(SeamKind.Terminal, "terminal")]
    [InlineData(SeamKind.Logging, "logging")]
    [InlineData(SeamKind.Metrics, "metrics")]
    public void It_should_name_every_seam(SeamKind value, string expected)
    {
        // Act
        var wire = SeamWire.Name(value);

        // Assert
        wire.Should().Be(expected);
    }

    [Theory]
    [InlineData("system", SeamKind.System)]
    [InlineData("vfs", SeamKind.Vfs)]
    [InlineData("terminal", SeamKind.Terminal)]
    [InlineData("logging", SeamKind.Logging)]
    [InlineData("metrics", SeamKind.Metrics)]
    public void It_should_parse_every_seam(string wire, SeamKind expected)
    {
        // Act
        var result = SeamWire.ParseSeamKind(wire);

        // Assert
        result.Should().BeOk(expected);
    }

    [Theory]
    [InlineData(LogLevel.Trace, "trace")]
    [InlineData(LogLevel.Debug, "debug")]
    [InlineData(LogLevel.Info, "info")]
    [InlineData(LogLevel.Warning, "warning")]
    [InlineData(LogLevel.Error, "error")]
    [InlineData(LogLevel.Fatal, "fatal")]
    public void It_should_name_every_log_level(LogLevel value, string expected)
    {
        // Act
        var wire = SeamWire.Name(value);

        // Assert
        wire.Should().Be(expected);
    }

    [Theory]
    [InlineData("trace", LogLevel.Trace)]
    [InlineData("debug", LogLevel.Debug)]
    [InlineData("info", LogLevel.Info)]
    [InlineData("warning", LogLevel.Warning)]
    [InlineData("error", LogLevel.Error)]
    [InlineData("fatal", LogLevel.Fatal)]
    public void It_should_parse_every_log_level(string wire, LogLevel expected)
    {
        // Act
        var result = SeamWire.ParseLogLevel(wire);

        // Assert
        result.Should().BeOk(expected);
    }

    [Theory]
    [InlineData(MetricKind.Counter, "counter")]
    [InlineData(MetricKind.Gauge, "gauge")]
    [InlineData(MetricKind.Histogram, "histogram")]
    public void It_should_name_every_metric_kind(MetricKind value, string expected)
    {
        // Act
        var wire = SeamWire.Name(value);

        // Assert
        wire.Should().Be(expected);
    }

    [Theory]
    [InlineData("counter", MetricKind.Counter)]
    [InlineData("gauge", MetricKind.Gauge)]
    [InlineData("histogram", MetricKind.Histogram)]
    public void It_should_parse_every_metric_kind(string wire, MetricKind expected)
    {
        // Act
        var result = SeamWire.ParseMetricKind(wire);

        // Assert
        result.Should().BeOk(expected);
    }

    [Theory]
    [InlineData(VfsEntryType.File, "file")]
    [InlineData(VfsEntryType.Directory, "directory")]
    [InlineData(VfsEntryType.Link, "link")]
    public void It_should_name_every_entry_type(VfsEntryType value, string expected)
    {
        // Act
        var wire = SeamWire.Name(value);

        // Assert
        wire.Should().Be(expected);
    }

    [Theory]
    [InlineData("file", VfsEntryType.File)]
    [InlineData("directory", VfsEntryType.Directory)]
    [InlineData("link", VfsEntryType.Link)]
    public void It_should_parse_every_entry_type(string wire, VfsEntryType expected)
    {
        // Act
        var result = SeamWire.ParseVfsEntryType(wire);

        // Assert
        result.Should().BeOk(expected);
    }

    [Theory]
    [InlineData(AttributeValueKind.Text, "text")]
    [InlineData(AttributeValueKind.Integer, "integer")]
    [InlineData(AttributeValueKind.Real, "real")]
    [InlineData(AttributeValueKind.Flag, "flag")]
    [InlineData(AttributeValueKind.Instant, "instant")]
    [InlineData(AttributeValueKind.Duration, "duration")]
    [InlineData(AttributeValueKind.TimeZone, "time_zone")]
    public void It_should_name_every_attribute_kind(AttributeValueKind value, string expected)
    {
        // Act
        var wire = SeamWire.Name(value);

        // Assert
        wire.Should().Be(expected);
    }

    [Theory]
    [InlineData("text", AttributeValueKind.Text)]
    [InlineData("integer", AttributeValueKind.Integer)]
    [InlineData("real", AttributeValueKind.Real)]
    [InlineData("flag", AttributeValueKind.Flag)]
    [InlineData("instant", AttributeValueKind.Instant)]
    [InlineData("duration", AttributeValueKind.Duration)]
    [InlineData("time_zone", AttributeValueKind.TimeZone)]
    public void It_should_parse_every_attribute_kind(string wire, AttributeValueKind expected)
    {
        // Act
        var result = SeamWire.ParseAttributeValueKind(wire);

        // Assert
        result.Should().BeOk(expected);
    }

    [Fact]
    public void It_should_reject_an_unknown_seam_name()
    {
        // Act
        var result = SeamWire.ParseSeamKind("nope");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_reject_an_unknown_log_level_name()
    {
        // Act
        var result = SeamWire.ParseLogLevel("nope");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_reject_an_unknown_metric_kind_name()
    {
        // Act
        var result = SeamWire.ParseMetricKind("nope");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_reject_an_unknown_entry_type_name()
    {
        // Act
        var result = SeamWire.ParseVfsEntryType("nope");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_reject_an_unknown_attribute_kind_name()
    {
        // Act
        var result = SeamWire.ParseAttributeValueKind("nope");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    // Naming throws by design: an undeclared value is a caller bug, not a seam failure.
    [Fact]
    public void It_should_refuse_to_name_a_seam_outside_its_enumeration()
    {
        // Act
        var act = () => SeamWire.Name((SeamKind)99);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void It_should_refuse_to_name_a_log_level_outside_its_enumeration()
    {
        // Act
        var act = () => SeamWire.Name((LogLevel)99);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void It_should_refuse_to_name_a_metric_kind_outside_its_enumeration()
    {
        // Act
        var act = () => SeamWire.Name((MetricKind)99);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void It_should_refuse_to_name_an_entry_type_outside_its_enumeration()
    {
        // Act
        var act = () => SeamWire.Name((VfsEntryType)99);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void It_should_refuse_to_name_an_attribute_kind_outside_its_enumeration()
    {
        // Act
        var act = () => SeamWire.Name((AttributeValueKind)99);

        // Assert
        act.Should().Throw<ArgumentOutOfRangeException>();
    }
}
