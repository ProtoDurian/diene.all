using System.Text.Json;
using AtomiCloud.Diene.Interfaces;
using AtomiCloud.Diene.Interfaces.TestHelper;

namespace AtomiCloud.DotnetBase.IntTest;

public class HostWireContractTests
{
    private static JsonElement Fixture { get; } = JsonDocument
        .Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "fixtures", "c0", "wire-v1.json")))
        .RootElement;

    private static string Pinned(string name) => Fixture.GetProperty(name).GetString()!;

    [Fact]
    public void It_should_resolve_the_pinned_zone_against_the_host_iana_database()
    {
        // Arrange
        var id = Pinned("timeZone");

        // Act
        var result = Wire.ParseTimeZone(id);

        // Assert
        var zone = result.Should().BeOk().Which;
        zone.HasIanaId.Should().BeTrue();
        zone.GetUtcOffset(new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero)).Should().Be(TimeSpan.FromHours(8));
    }

    [Fact]
    public void It_should_refuse_a_windows_zone_id_even_where_the_host_can_map_it()
    {
        // Act
        var result = Wire.ParseTimeZone("Singapore Standard Time");

        // Assert
        result.Should().BeErr(new WireFormatError("IANA timezone id", "Singapore Standard Time"));
    }

    [Fact]
    public void It_should_write_the_demo_receipt_in_the_fixture_pinned_forms()
    {
        // Arrange
        var receipt = Samples.Sample().Should().BeOk().Which;

        // Act
        var json = JsonDocument.Parse(Samples.ToWire(receipt)).RootElement;

        // Assert
        json.GetProperty("shippedOn").GetString().Should().Be(Pinned("date"));
        json.GetProperty("cutoff").GetString().Should().Be(Pinned("time"));
        json.GetProperty("confirmedAt").GetString().Should().Be(Pinned("instant"));
        json.GetProperty("originZone").GetString().Should().Be(Pinned("timeZone"));
        json.GetProperty("declaredValue").GetString().Should().Be(Pinned("decimal"));
        json.GetProperty("trackingNumber").GetString().Should().Be(Pinned("int64"));
        json.GetProperty("transitTime").GetString().Should().Be("PT1H30M");
    }

    [Fact]
    public void It_should_read_back_the_demo_receipt_it_wrote()
    {
        // Arrange
        var receipt = Samples.Sample().Should().BeOk().Which;
        var wire = Samples.ToWire(receipt);

        // Act
        var result = Samples.FromWire(wire);

        // Assert
        result.Should().BeOk(receipt);
    }

    [Fact]
    public void It_should_report_a_malformed_payload_instead_of_throwing()
    {
        // Act
        var result = Samples.FromWire("""{"shippedOn":"25-07-2026"}""");

        // Assert
        result.Should().BeErr().Which.Expected.Should().Be("shipment receipt");
    }

    [Fact]
    public void It_should_report_a_null_payload_as_a_rejected_receipt()
    {
        // Act
        var result = Samples.FromWire("null");

        // Assert
        result.Should().BeErr(new WireFormatError("shipment receipt", "null"));
    }

    [Fact]
    public void It_should_compose_a_catalog_key_from_untrusted_text()
    {
        // Act
        var result = Samples.CatalogKey("AtomiCloud", "Express Parcel");

        // Assert
        result.Should().BeOk("atomicloud:express-parcel");
    }

    [Fact]
    public void It_should_reject_a_catalog_key_whose_namespace_slugifies_to_empty()
    {
        // Act
        var result = Samples.CatalogKey("!!!", "Express Parcel");

        // Assert
        result.Should().BeErr(new KeyError("namespace must not be empty", "!!!"));
    }

    [Fact]
    public void It_should_deliver_normalized_wire_attributes_to_a_seam()
    {
        // Arrange
        var receipt = Samples.Sample().Should().BeOk().Which;
        var sink = new InMemoryLoggerSink();
        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;
        var record = new LogRecord(receipt.ConfirmedAt, LogLevel.Info, "shipment confirmed", attributes);

        // Act
        var emitted = sink.Emit(record);

        // Assert
        emitted.Should().BeOk();
        var recorded = sink.Records.Should().ContainSingle().Which.Attributes;
        recorded.Keys.Should().BeEquivalentTo(
            "shipmentreference", "shippedon", "dailycutoff", "declaredvalue",
            "confirmedat", "transittime", "trackingnumber");
        recorded["declaredvalue"].Wire.Should().Be(Pinned("decimal"));
        recorded["confirmedat"].Kind.Should().Be(AttributeValueKind.Instant);
    }

    [Fact]
    public void It_should_reject_a_null_receipt_in_telemetry()
    {
        // Act
        var act = FluentActions.Invoking(() => Samples.Telemetry(null!));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_read_an_attribute_back_under_a_pascal_case_key_spelling()
    {
        // Arrange
        var receipt = Samples.Sample().Should().BeOk().Which;
        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;

        // Act
        var result = Samples.Lookup(attributes, "TrackingNumber");

        // Assert
        result.Should().BeOk().Which.Wire.Should().Be(Pinned("int64"));
    }

    [Fact]
    public void It_should_read_an_attribute_back_under_a_kebab_case_key_spelling()
    {
        // Arrange
        var receipt = Samples.Sample().Should().BeOk().Which;
        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;

        // Act
        var result = Samples.Lookup(attributes, "shipped-on");

        // Assert
        result.Should().BeOk().Which.Wire.Should().Be(Pinned("date"));
    }

    [Fact]
    public void It_should_report_an_attribute_key_that_matches_nothing()
    {
        // Arrange
        var receipt = Samples.Sample().Should().BeOk().Which;
        var attributes = Samples.Telemetry(receipt).Should().BeOk().Which;

        // Act
        var result = Samples.Lookup(attributes, "carrier");

        // Assert
        var missing = result.Should().BeErr().Which;
        missing.Reason.Should().Be("no attribute matches the key");
        missing.Offending.Should().Be("carrier");
    }

    [Fact]
    public void It_should_reject_a_null_attribute_map_in_lookup()
    {
        // Act
        var act = FluentActions.Invoking(() => Samples.Lookup(null!, "key"));

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }
}
