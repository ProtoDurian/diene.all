namespace AtomiCloud.DotnetBase.App;

public sealed record ShipmentReceipt
{
    public required string Reference { get; init; }

    public required DateOnly ShippedOn { get; init; }

    public required TimeOnly Cutoff { get; init; }

    public required DateTimeOffset ConfirmedAt { get; init; }

    public required TimeSpan TransitTime { get; init; }

    public required TimeZoneInfo OriginZone { get; init; }

    public required decimal DeclaredValue { get; init; }

    public required long TrackingNumber { get; init; }
}
