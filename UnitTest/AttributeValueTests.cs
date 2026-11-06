namespace AtomiCloud.DotnetBase.UnitTest;

public class AttributeValueTests
{
    private static readonly DateTimeOffset Anchor = new(2026, 7, 25, 22, 30, 0, TimeSpan.Zero);

    [Fact]
    public void It_should_store_text_verbatim()
    {
        // Act
        var value = AttributeValue.Text("value");

        // Assert
        value.Kind.Should().Be(AttributeValueKind.Text);
        value.Wire.Should().Be("value");
        value.AsText().Should().Be("value");
    }

    [Fact]
    public void It_should_reject_null_text()
    {
        // Act
        var act = () => AttributeValue.Text(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_render_an_uninitialized_value_as_empty_text()
    {
        // Arrange
        var value = default(AttributeValue);

        // Act
        var wire = value.Wire;

        // Assert
        wire.Should().BeEmpty();
    }

    [Fact]
    public void It_should_round_trip_an_integer()
    {
        // Arrange
        var value = AttributeValue.Integer(42);

        // Act
        var actual = value.AsInteger();

        // Assert
        actual.Should().BeOk(42L);
    }

    [Fact]
    public void It_should_round_trip_a_real()
    {
        // Arrange
        var value = AttributeValue.Real(1.5);

        // Act
        var actual = value.AsReal();

        // Assert
        actual.Should().BeOk(1.5);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void It_should_round_trip_a_flag(bool flag)
    {
        // Arrange
        var value = AttributeValue.Flag(flag);

        // Act
        var actual = value.AsFlag();

        // Assert
        actual.Should().BeOk(flag);
    }

    [Fact]
    public void It_should_round_trip_an_instant()
    {
        // Arrange
        var value = AttributeValue.Instant(Anchor);

        // Act
        var actual = value.AsInstant();

        // Assert
        actual.Should().BeOk(Anchor);
    }

    [Fact]
    public void It_should_round_trip_a_duration()
    {
        // Arrange
        var value = AttributeValue.Duration(TimeSpan.FromSeconds(90));

        // Act
        var actual = value.AsDuration();

        // Assert
        actual.Should().BeOk(TimeSpan.FromSeconds(90));
    }

    [Fact]
    public void It_should_round_trip_a_timezone()
    {
        // Arrange
        var value = AttributeValue.TimeZone(TimeZoneInfo.Utc.Id).Should().BeOk().Which;

        // Act
        var actual = value.AsTimeZone();

        // Assert
        actual.Should().BeOk();
    }

    [Fact]
    public void It_should_render_an_integer_on_the_wire()
    {
        // Act
        var wire = AttributeValue.Integer(42).Wire;

        // Assert
        wire.Should().Be("42");
    }

    [Fact]
    public void It_should_render_a_real_on_the_wire()
    {
        // Act
        var wire = AttributeValue.Real(1.5).Wire;

        // Assert
        wire.Should().Be("1.5");
    }

    [Theory]
    [InlineData(true, "true")]
    [InlineData(false, "false")]
    public void It_should_render_a_flag_on_the_wire(bool flag, string expected)
    {
        // Act
        var wire = AttributeValue.Flag(flag).Wire;

        // Assert
        wire.Should().Be(expected);
    }

    [Fact]
    public void It_should_render_an_instant_on_the_wire()
    {
        // Act
        var wire = AttributeValue.Instant(Anchor).Wire;

        // Assert
        wire.Should().Be("2026-07-25T22:30:00.0000000Z");
    }

    [Fact]
    public void It_should_render_a_duration_on_the_wire()
    {
        // Act
        var wire = AttributeValue.Duration(TimeSpan.FromSeconds(90)).Wire;

        // Assert
        wire.Should().Be("PT1M30S");
    }

    [Fact]
    public void It_should_reject_an_unresolvable_timezone()
    {
        // Act
        var result = AttributeValue.TimeZone("Mars/Olympus");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "unknown_time_zone");
    }

    [Fact]
    public void It_should_refuse_to_read_text_as_an_integer()
    {
        // Arrange
        var text = AttributeValue.Text("value");

        // Act
        var result = text.AsInteger();

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_refuse_to_read_text_as_a_real()
    {
        // Arrange
        var text = AttributeValue.Text("value");

        // Act
        var result = text.AsReal();

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_refuse_to_read_text_as_a_flag()
    {
        // Arrange
        var text = AttributeValue.Text("value");

        // Act
        var result = text.AsFlag();

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_refuse_to_read_text_as_an_instant()
    {
        // Arrange
        var text = AttributeValue.Text("value");

        // Act
        var result = text.AsInstant();

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_refuse_to_read_text_as_a_duration()
    {
        // Arrange
        var text = AttributeValue.Text("value");

        // Act
        var result = text.AsDuration();

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_refuse_to_read_text_as_a_timezone()
    {
        // Arrange
        var text = AttributeValue.Text("value");

        // Act
        var result = text.AsTimeZone();

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_rebuild_text_from_the_wire()
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.Text, "value");

        // Assert
        result.Should().BeOk(AttributeValue.Text("value"));
    }

    [Fact]
    public void It_should_rebuild_an_integer_from_the_wire()
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.Integer, "42");

        // Assert
        result.Should().BeOk(AttributeValue.Integer(42));
    }

    [Fact]
    public void It_should_rebuild_a_real_from_the_wire()
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.Real, "1.5");

        // Assert
        result.Should().BeOk(AttributeValue.Real(1.5));
    }

    [Theory]
    [InlineData("true", true)]
    [InlineData("false", false)]
    public void It_should_rebuild_a_flag_from_the_wire(string wire, bool expected)
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.Flag, wire);

        // Assert
        result.Should().BeOk(AttributeValue.Flag(expected));
    }

    [Fact]
    public void It_should_rebuild_an_instant_from_the_wire()
    {
        // Arrange
        var wire = SeamWire.Instant(Anchor);

        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.Instant, wire);

        // Assert
        result.Should().BeOk(AttributeValue.Instant(Anchor));
    }

    [Fact]
    public void It_should_rebuild_a_duration_from_the_wire()
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.Duration, "PT1M30S");

        // Assert
        result.Should().BeOk(AttributeValue.Duration(TimeSpan.FromSeconds(90)));
    }

    [Fact]
    public void It_should_rebuild_a_timezone_from_the_wire()
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.TimeZone, TimeZoneInfo.Utc.Id);

        // Assert
        result.Should().BeOk();
    }

    [Theory]
    [InlineData(AttributeValueKind.Integer, "twelve")]
    [InlineData(AttributeValueKind.Real, "one point five")]
    [InlineData(AttributeValueKind.Flag, "yes")]
    [InlineData(AttributeValueKind.Instant, "yesterday")]
    [InlineData(AttributeValueKind.Duration, "90s")]
    public void It_should_reject_a_malformed_wire_payload(AttributeValueKind kind, string wire)
    {
        // Act
        var result = AttributeValue.FromWire(kind, wire);

        // Assert
        result.Should().BeErr();
    }

    [Fact]
    public void It_should_reject_an_undeclared_wire_kind()
    {
        // Act
        var result = AttributeValue.FromWire((AttributeValueKind)99, "value");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "invalid_wire");
    }

    [Fact]
    public void It_should_reject_an_unresolvable_timezone_from_the_wire()
    {
        // Act
        var result = AttributeValue.FromWire(AttributeValueKind.TimeZone, "Mars/Olympus");

        // Assert
        result.Should().BeSeamErr(SeamKind.Logging, "unknown_time_zone");
    }

    [Fact]
    public void It_should_equal_a_value_of_the_same_kind_and_wire()
    {
        // Arrange
        var left = AttributeValue.Integer(42);
        var right = AttributeValue.Integer(42);

        // Act
        var equal = left.Equals(right);

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_equal_a_boxed_value_of_the_same_kind_and_wire()
    {
        // Arrange
        var left = AttributeValue.Integer(42);
        object right = AttributeValue.Integer(42);

        // Act
        var equal = left.Equals(right);

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_not_equal_an_object_of_another_type()
    {
        // Arrange
        var value = AttributeValue.Integer(42);

        // Act
        var equal = value.Equals("42");

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_not_equal_a_value_of_another_kind_with_the_same_wire()
    {
        // Arrange
        var left = AttributeValue.Integer(42);
        var other = AttributeValue.Text("42");

        // Act
        var equal = left.Equals(other);

        // Assert
        equal.Should().BeFalse();
    }

    [Fact]
    public void It_should_compare_equal_values_with_the_equality_operator()
    {
        // Arrange
        var left = AttributeValue.Integer(42);
        var right = AttributeValue.Integer(42);

        // Act
        var equal = left == right;

        // Assert
        equal.Should().BeTrue();
    }

    [Fact]
    public void It_should_compare_values_of_different_kinds_with_the_inequality_operator()
    {
        // Arrange
        var left = AttributeValue.Integer(42);
        var other = AttributeValue.Text("42");

        // Act
        var unequal = left != other;

        // Assert
        unequal.Should().BeTrue();
    }

    [Fact]
    public void It_should_share_a_hash_code_with_an_equal_value()
    {
        // Arrange
        var left = AttributeValue.Integer(42);
        var right = AttributeValue.Integer(42);

        // Act
        var hash = left.GetHashCode();

        // Assert
        hash.Should().Be(right.GetHashCode());
    }

    [Fact]
    public void It_should_render_kind_and_wire()
    {
        // Arrange
        var value = AttributeValue.Duration(TimeSpan.FromSeconds(90));

        // Act
        var rendered = value.ToString();

        // Assert
        rendered.Should().Be("duration:PT1M30S");
    }

    [Fact]
    public void It_should_copy_attribute_maps_in_key_order()
    {
        // Arrange
        KeyValuePair<string, AttributeValue>[] source =
        [
            new("beta", AttributeValue.Integer(2)),
            new("alpha", AttributeValue.Integer(1)),
        ];

        // Act
        var attributes = SeamAttributes.Copy(source);

        // Assert
        attributes.Keys.Should().ContainInOrder("alpha", "beta");
    }

    [Fact]
    public void It_should_copy_a_null_attribute_map_as_the_shared_empty_map()
    {
        // Act
        var attributes = SeamAttributes.Copy(null);

        // Assert
        attributes.Should().BeSameAs(SeamAttributes.Empty);
    }

    [Fact]
    public void It_should_publish_an_empty_attribute_map()
    {
        // Act
        var empty = SeamAttributes.Empty;

        // Assert
        empty.Should().BeEmpty();
    }
}
