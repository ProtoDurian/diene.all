namespace AtomiCloud.DotnetBase.UnitTest;

public class WireTests
{
    [Theory]
    [InlineData("2026-07-25", 2026, 7, 25)]
    [InlineData("0001-01-01", 1, 1, 1)]
    public void It_should_parse_a_canonical_date(string wire, int year, int month, int day)
    {
        // Act
        var actual = Wire.ParseDate(wire);

        // Assert
        actual.Should().BeOk(new DateOnly(year, month, day));
    }

    [Theory]
    [InlineData("25-07-2026")]
    [InlineData("2026-7-25")]
    [InlineData("2026-02-30")]
    [InlineData("2026-07-25T00:00:00Z")]
    [InlineData("")]
    public void It_should_reject_a_non_canonical_date(string wire)
    {
        // Act
        var actual = Wire.ParseDate(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("yyyy-MM-dd", wire));
    }

    [Fact]
    public void It_should_render_a_date_in_the_canonical_form()
    {
        // Act
        var actual = Wire.Format(new DateOnly(2026, 7, 25));

        // Assert
        actual.Should().Be("2026-07-25");
    }

    [Theory]
    [InlineData("17:30:00", 17, 30, 0)]
    [InlineData("00:00:00", 0, 0, 0)]
    [InlineData("23:59:59", 23, 59, 59)]
    public void It_should_parse_a_canonical_time(string wire, int hour, int minute, int second)
    {
        // Act
        var actual = Wire.ParseTime(wire);

        // Assert
        actual.Should().BeOk(new TimeOnly(hour, minute, second));
    }

    [Theory]
    [InlineData("17:30")]
    [InlineData("17:30:00.500")]
    [InlineData("5:30:00 PM")]
    [InlineData("24:00:00")]
    public void It_should_reject_a_non_canonical_time(string wire)
    {
        // Act
        var actual = Wire.ParseTime(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("HH:mm:ss", wire));
    }

    [Fact]
    public void It_should_render_a_time_in_the_canonical_form()
    {
        // Act
        var actual = Wire.Format(new TimeOnly(17, 30, 0));

        // Assert
        actual.Should().Be("17:30:00");
    }

    [Fact]
    public void It_should_truncate_sub_second_precision_when_rendering_a_time()
    {
        // Act
        var actual = Wire.Format(new TimeOnly(17, 30, 0, 500));

        // Assert
        actual.Should().Be("17:30:00");
    }

    [Fact]
    public void It_should_parse_a_utc_instant()
    {
        // Act
        var actual = Wire.ParseInstant("2026-07-25T22:30:00Z");

        // Assert
        actual.Should().BeOk(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero));
    }

    [Fact]
    public void It_should_accept_a_lowercase_designator()
    {
        // Act
        var actual = Wire.ParseInstant("2026-07-25t22:30:00z");

        // Assert
        actual.Should().BeOk(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero));
    }

    [Fact]
    public void It_should_normalize_an_offset_instant_to_utc()
    {
        // Act
        var actual = Wire.ParseInstant("2026-07-26T06:30:00+08:00");

        // Assert
        actual.Should().BeOk(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero));
    }

    [Fact]
    public void It_should_keep_fractional_seconds_within_tick_precision()
    {
        // Act
        var actual = Wire.ParseInstant("2026-07-25T22:30:00.1234567Z");

        // Assert
        actual.Should().BeOk(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero).AddTicks(1234567));
    }

    [Fact]
    public void It_should_truncate_fractional_digits_below_tick_precision()
    {
        // Act
        var actual = Wire.ParseInstant("2026-07-25T22:30:00.123456789Z");

        // Assert
        actual.Should().BeOk(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero).AddTicks(1234567));
    }

    [Theory]
    [InlineData("2026-07-25 22:30:00Z")]
    [InlineData("2026-07-25T22:30:00")]
    [InlineData("2026-07-25T22:30Z")]
    [InlineData("2026-13-25T22:30:00Z")]
    [InlineData("not-an-instant")]
    public void It_should_reject_a_non_rfc3339_instant(string wire)
    {
        // Act
        var actual = Wire.ParseInstant(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("RFC 3339 instant", wire));
    }

    [Fact]
    public void It_should_render_an_instant_without_a_fraction_when_it_is_whole()
    {
        // Act
        var actual = Wire.Format(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero));

        // Assert
        actual.Should().Be("2026-07-25T22:30:00Z");
    }

    [Fact]
    public void It_should_render_an_instant_with_trimmed_fractional_digits()
    {
        // Arrange
        var instant = new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero).AddTicks(5000000);

        // Act
        var actual = Wire.Format(instant);

        // Assert
        actual.Should().Be("2026-07-25T22:30:00.5Z");
    }

    [Fact]
    public void It_should_render_an_offset_instant_as_utc()
    {
        // Act
        var actual = Wire.Format(new DateTimeOffset(2026, 7, 26, 6, 30, 0, TimeSpan.FromHours(8)));

        // Assert
        actual.Should().Be("2026-07-25T22:30:00Z");
    }

    [Theory]
    [InlineData("PT0S", 0)]
    [InlineData("PT1M30S", 90)]
    [InlineData("PT1H30M", 5400)]
    [InlineData("P2DT3H4M5S", 183845)]
    [InlineData("P1D", 86400)]
    [InlineData("-PT1M30S", -90)]
    public void It_should_parse_an_iso8601_duration(string wire, double seconds)
    {
        // Act
        var actual = Wire.ParseDuration(wire);

        // Assert
        actual.Should().BeOk(TimeSpan.FromSeconds(seconds));
    }

    [Fact]
    public void It_should_parse_fractional_duration_seconds()
    {
        // Act
        var actual = Wire.ParseDuration("PT0.5S");

        // Assert
        actual.Should().BeOk(TimeSpan.FromMilliseconds(500));
    }

    [Theory]
    [InlineData("P1Y")]
    [InlineData("P1M")]
    [InlineData("P1W")]
    [InlineData("P")]
    [InlineData("PT")]
    [InlineData("90s")]
    [InlineData("")]
    public void It_should_reject_a_duration_outside_the_contract(string wire)
    {
        // Act
        var actual = Wire.ParseDuration(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("ISO 8601 duration", wire));
    }

    [Theory]
    [InlineData(0, "PT0S")]
    [InlineData(90, "PT1M30S")]
    [InlineData(5400, "PT1H30M")]
    [InlineData(86400, "P1D")]
    [InlineData(183845, "P2DT3H4M5S")]
    [InlineData(-90, "-PT1M30S")]
    public void It_should_render_a_duration_in_the_canonical_spelling(double seconds, string expected)
    {
        // Act
        var actual = Wire.Format(TimeSpan.FromSeconds(seconds));

        // Assert
        actual.Should().Be(expected);
    }

    [Fact]
    public void It_should_render_fractional_duration_seconds()
    {
        // Act
        var actual = Wire.Format(TimeSpan.FromMilliseconds(1500));

        // Assert
        actual.Should().Be("PT1.5S");
    }

    [Theory]
    [InlineData("PT0S")]
    [InlineData("PT1M30S")]
    [InlineData("PT1H30M")]
    [InlineData("P1D")]
    [InlineData("P2DT3H4M5S")]
    [InlineData("PT0.5S")]
    [InlineData("-PT1M30S")]
    public void It_should_round_trip_every_canonical_duration_spelling(string wire)
    {
        // Act
        var actual = Wire.Format(Wire.ParseDuration(wire).Should().BeOk().Which);

        // Assert
        actual.Should().Be(wire);
    }

    [Fact]
    public void It_should_resolve_an_iana_timezone()
    {
        // Act
        var actual = Wire.ParseTimeZone("Asia/Singapore");

        // Assert
        actual.Should().BeOk().Which.Id.Should().Be("Asia/Singapore");
    }

    [Theory]
    [InlineData("Singapore Standard Time")]
    [InlineData("+08:00")]
    [InlineData("Middle/Earth")]
    [InlineData("")]
    public void It_should_reject_a_timezone_that_is_not_a_known_iana_id(string wire)
    {
        // Act
        var actual = Wire.ParseTimeZone(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("IANA timezone id", wire));
    }

    [Fact]
    public void It_should_render_a_timezone_as_its_iana_id()
    {
        // Arrange
        var zone = Wire.ParseTimeZone("Asia/Singapore").Should().BeOk().Which;

        // Act
        var actual = Wire.Format(zone);

        // Assert
        actual.Should().Be("Asia/Singapore");
    }

    [Fact]
    public void It_should_reject_a_null_timezone()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.Format((TimeZoneInfo)null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Theory]
    [InlineData("1249.50", "1249.50")]
    [InlineData("-0.01", "-0.01")]
    [InlineData("0", "0")]
    public void It_should_round_trip_a_decimal_string(string wire, string expected)
    {
        // Act
        var actual = Wire.Format(Wire.ParseDecimal(wire).Should().BeOk().Which);

        // Assert
        actual.Should().Be(expected);
    }

    [Theory]
    [InlineData("1,249.50")]
    [InlineData("1.2e3")]
    [InlineData("abc")]
    [InlineData("")]
    public void It_should_reject_a_decimal_that_is_not_a_plain_decimal_string(string wire)
    {
        // Act
        var actual = Wire.ParseDecimal(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("decimal string", wire));
    }

    [Fact]
    public void It_should_round_trip_an_int64_beyond_the_json_safe_range()
    {
        // Act
        var actual = Wire.Format(Wire.ParseInt64("9007199254740993").Should().BeOk().Which);

        // Assert
        actual.Should().Be("9007199254740993");
    }

    [Theory]
    [InlineData("9223372036854775808")]
    [InlineData("1.5")]
    [InlineData("")]
    public void It_should_reject_a_non_int64_string(string wire)
    {
        // Act
        var actual = Wire.ParseInt64(wire);

        // Assert
        actual.Should().BeErr(new WireFormatError("int64 string", wire));
    }

    [Fact]
    public void It_should_reject_a_null_date_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseDate(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_time_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseTime(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_instant_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseInstant(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_duration_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseDuration(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_timezone_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseTimeZone(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_decimal_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseDecimal(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_null_int64_payload()
    {
        // Act
        var act = FluentActions.Invoking(() => Wire.ParseInt64(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
