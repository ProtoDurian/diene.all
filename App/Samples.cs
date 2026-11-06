using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.Diene.Interfaces;

namespace AtomiCloud.DotnetBase.App;

public static class Samples
{
    public static Result<string, KeyError> CatalogKey(string ns, string title) => Slug.NamespacedKey(ns, title);

    public static string ToWire(ShipmentReceipt receipt) =>
        JsonSerializer.Serialize(receipt, AtomiJson.DefaultOptions);

    public static Result<ShipmentReceipt, WireFormatError> FromWire(string json)
    {
        try
        {
            var receipt = JsonSerializer.Deserialize<ShipmentReceipt>(json, AtomiJson.DefaultOptions);
            return receipt is null
                ? Result.Err<ShipmentReceipt, WireFormatError>(new WireFormatError("shipment receipt", json))
                : Result.Ok<ShipmentReceipt, WireFormatError>(receipt);
        }
        catch (JsonException exception)
        {
            return Result.Err<ShipmentReceipt, WireFormatError>(
                new WireFormatError("shipment receipt", exception.Message));
        }
    }

    public static Result<IReadOnlyDictionary<string, AttributeValue>, KeyError> Telemetry(ShipmentReceipt receipt)
    {
        ArgumentNullException.ThrowIfNull(receipt);
        return WireAttributes.Normalize(new Dictionary<string, AttributeValue>(StringComparer.Ordinal)
        {
            ["shipment_reference"] = AttributeValue.Text(receipt.Reference),
            ["shipped-on"] = WireAttributes.Date(receipt.ShippedOn),
            ["dailyCutoff"] = WireAttributes.Time(receipt.Cutoff),
            ["DeclaredValue"] = WireAttributes.Decimal(receipt.DeclaredValue),
            ["confirmed_at"] = AttributeValue.Instant(receipt.ConfirmedAt),
            ["transit_time"] = AttributeValue.Duration(receipt.TransitTime),
            ["tracking_number"] = AttributeValue.Integer(receipt.TrackingNumber),
        });
    }

    public static Result<AttributeValue, KeyError> Lookup(
        IReadOnlyDictionary<string, AttributeValue> attributes,
        string key)
    {
        ArgumentNullException.ThrowIfNull(attributes);
        foreach (var (candidate, value) in attributes)
        {
            if (KeyNormalizer.KeysMatch(candidate, key)) return Result.Ok<AttributeValue, KeyError>(value);
        }

        return Result.Err<AttributeValue, KeyError>(new KeyError("no attribute matches the key", key));
    }

    public static Result<ShipmentReceipt, WireFormatError> Sample() =>
        Wire.ParseTimeZone("Asia/Singapore").Map(zone => new ShipmentReceipt
        {
            Reference = CatalogKey("AtomiCloud", "Express Parcel").GetOr("shipment"),
            ShippedOn = new DateOnly(2026, 7, 25),
            Cutoff = new TimeOnly(17, 30, 0),
            ConfirmedAt = new DateTimeOffset(2026, 7, 25, 22, 30, 0, TimeSpan.Zero),
            TransitTime = TimeSpan.FromMinutes(90),
            OriginZone = zone,
            DeclaredValue = 1249.50m,
            TrackingNumber = 9007199254740993L,
        });
}
