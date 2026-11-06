using AtomiCloud.Diene.Interfaces;
using AtomiCloud.Diene.Interfaces.TestHelper;

namespace AtomiCloud.DotnetBase.UnitTest;

public class WireAttributesTests
{
    [Fact]
    public void It_should_carry_a_date_as_its_wire_form()
    {
        // Act
        var attribute = WireAttributes.Date(new DateOnly(2026, 7, 25));

        // Assert
        attribute.Wire.Should().Be("2026-07-25");
    }

    [Fact]
    public void It_should_carry_a_time_as_its_wire_form()
    {
        // Act
        var attribute = WireAttributes.Time(new TimeOnly(17, 30, 0));

        // Assert
        attribute.Wire.Should().Be("17:30:00");
    }

    [Fact]
    public void It_should_carry_an_exact_decimal_as_a_string_rather_than_the_real_kind()
    {
        // Act
        var attribute = WireAttributes.Decimal(1249.50m);

        // Assert
        attribute.Wire.Should().Be("1249.50");
        attribute.Kind.Should().Be(AttributeValueKind.Text);
    }

    [Fact]
    public void It_should_normalize_keys_so_differently_spelled_attributes_aggregate()
    {
        // Arrange
        var source = new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["request_id"] = AttributeValue.Text("abc"),
            ["shipped-on"] = WireAttributes.Date(new DateOnly(2026, 7, 25)),
            ["DailyCutoff"] = WireAttributes.Time(new TimeOnly(17, 30, 0)),
        };

        // Act
        var result = WireAttributes.Normalize(source);

        // Assert
        var normalized = result.Should().BeOk().Which;
        normalized.Keys.Should().BeEquivalentTo("requestid", "shippedon", "dailycutoff");
        normalized["shippedon"].Wire.Should().Be("2026-07-25");
    }

    [Fact]
    public void It_should_reject_a_key_that_normalizes_to_nothing()
    {
        // Arrange
        var source = new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["__"] = AttributeValue.Text("orphan"),
        };

        // Act
        var result = WireAttributes.Normalize(source);

        // Assert
        result.Should().BeErr(new KeyError("attribute key must not normalize to empty", "__"));
    }

    [Fact]
    public void It_should_reject_two_keys_that_collide_once_normalized()
    {
        // Arrange
        KeyValuePair<string, AttributeValue>[] source =
        [
            new("request_id", AttributeValue.Text("first")),
            new("requestId", AttributeValue.Text("second")),
        ];

        // Act
        var result = WireAttributes.Normalize(source);

        // Assert
        result.Should().BeErr(new KeyError("attribute key collides with another key at \"requestid\"", "requestId"));
    }

    [Fact]
    public void It_should_reject_a_null_attribute_source()
    {
        // Act
        var act = FluentActions.Invoking(() => WireAttributes.Normalize(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reach_a_seam_that_a_consumer_fakes()
    {
        // Arrange
        var sink = new InMemoryLoggerSink();
        var attributes = WireAttributes.Normalize(new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["shipped-on"] = WireAttributes.Date(new DateOnly(2026, 7, 25)),
            ["declared_value"] = WireAttributes.Decimal(1249.50m),
        }).Should().BeOk().Which;
        var record = new LogRecord(
            new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero),
            LogLevel.Info,
            "shipment confirmed",
            attributes);

        // Act
        var emitted = sink.Emit(record);

        // Assert
        emitted.Should().BeOk();
        sink.Records.Should().ContainSingle()
            .Which.Attributes.Should().Contain(new KeyValuePair<string, AttributeValue>(
                "shippedon", WireAttributes.Date(new DateOnly(2026, 7, 25))));
    }
}
