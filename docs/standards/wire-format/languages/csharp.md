# Wire Format: C#/.NET

`System.Text.Json` produces every row of [Wire Format](../index.md) with one
`JsonSerializerOptions`. Build it once and pass it to every `JsonSerializer` call.
In ASP.NET Core, add the same settings and converters to `o.SerializerOptions`
inside `ConfigureHttpJsonOptions` (and `AddJsonOptions` for MVC).

```csharp
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Xml;

public static class Wire
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters =
        {
            new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false),
            new InstantConverter(),
            new DurationConverter(),
            new DecimalStringConverter(),
            new Int64StringConverter(),
        },
    };
}

public sealed class InstantConverter : JsonConverter<DateTimeOffset>
{
    private const string Format = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'";

    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
        DateTimeOffset.TryParseExact(reader.GetString(), Format, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value)
            ? value
            : throw new JsonException("Expected an instant like 2024-03-15T14:30:00.000Z.");

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.UtcDateTime.ToString(Format, CultureInfo.InvariantCulture));
}

public sealed class DurationConverter : JsonConverter<TimeSpan>
{
    public override TimeSpan Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
    {
        var text = reader.GetString() ?? "";
        // XmlConvert reads P1M as 30 days and P1Y as 365 days; calendar units are not durations.
        if (text.Split('T')[0].IndexOfAny(['Y', 'M']) >= 0)
        {
            throw new JsonException("Expected a duration in days, hours, minutes and seconds.");
        }

        try
        {
            return XmlConvert.ToTimeSpan(text);
        }
        catch (FormatException e)
        {
            throw new JsonException("Expected an ISO 8601 duration like PT2H30M.", e);
        }
    }

    public override void Write(Utf8JsonWriter writer, TimeSpan value, JsonSerializerOptions options) =>
        writer.WriteStringValue(XmlConvert.ToString(value));
}

public sealed class DecimalStringConverter : JsonConverter<decimal>
{
    public override decimal Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
        decimal.TryParse(reader.GetString(), NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value)
            ? value
            : throw new JsonException("Expected a decimal string like \"12.50\".");

    public override void Write(Utf8JsonWriter writer, decimal value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString(CultureInfo.InvariantCulture));
}

public sealed class Int64StringConverter : JsonConverter<long>
{
    public override long Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
        long.TryParse(reader.GetString(), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var value)
            ? value
            : throw new JsonException("Expected an integer string like \"9007199254740993\".");

    public override void Write(Utf8JsonWriter writer, long value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString(CultureInfo.InvariantCulture));
}
```

The defaults that need a converter: `DateTimeOffset` writes `+00:00` and up to 7
fractional digits, `TimeSpan` writes `02:30:00`, and `decimal` and `long` write
JSON numbers that lose precision in JavaScript readers. Every `long` field is a
string, so its wire type never depends on its value; use `int` for counts that
fit in a JSON number. Each converter throws `JsonException` on bad input, which
ASP.NET Core answers with a 400.

## Keys

```csharp
public sealed record Order(Guid OrderId);

JsonSerializer.Serialize(new Order(orderId), Wire.Options); // {"orderId":"..."}
```

## UUID

```csharp
JsonSerializer.Serialize(new Order(Guid.CreateVersion7()), Wire.Options); // lowercase v7
```

## Instant

```csharp
public sealed record Created(DateTimeOffset At);

var json = JsonSerializer.Serialize(new Created(DateTimeOffset.Parse("2024-03-15T22:30:00+08:00")), Wire.Options);
// {"at":"2024-03-15T14:30:00.000Z"}
var at = JsonSerializer.Deserialize<Created>(json, Wire.Options)!.At; // 14:30 UTC, offset 00:00
```

## Date

```csharp
public sealed record Billing(DateOnly Day);

JsonSerializer.Serialize(new Billing(new DateOnly(2024, 3, 15)), Wire.Options); // {"day":"2024-03-15"}
```

## Time of day

```csharp
public sealed record Opening(TimeOnly OpensAt);

JsonSerializer.Serialize(new Opening(new TimeOnly(14, 30)), Wire.Options); // {"opensAt":"14:30:00"}
```

The default `TimeOnly` converter already writes `HH:mm:ss`. Keep values at whole
seconds, because a fraction would be written too.

## Zoned value

```csharp
public sealed record Meeting(DateTimeOffset At, string Zone);

var zone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Singapore");
var json = JsonSerializer.Serialize(new Meeting(startsAt, zone.Id), Wire.Options);
// {"at":"2024-03-15T14:30:00.000Z","zone":"Asia/Singapore"}
var meeting = JsonSerializer.Deserialize<Meeting>(json, Wire.Options)!;
var local = TimeZoneInfo.ConvertTime(meeting.At, TimeZoneInfo.FindSystemTimeZoneById(meeting.Zone));
```

## Duration

```csharp
public sealed record Retry(TimeSpan Timeout);

var json = JsonSerializer.Serialize(new Retry(new TimeSpan(2, 30, 0)), Wire.Options); // {"timeout":"PT2H30M"}
var timeout = JsonSerializer.Deserialize<Retry>(json, Wire.Options)!.Timeout; // 02:30:00
JsonSerializer.Serialize(new Retry(new TimeSpan(1, 2, 0, 0)), Wire.Options); // {"timeout":"P1DT2H"}
```

## Money / decimal

```csharp
public sealed record Money(decimal Amount, string Currency);

var json = JsonSerializer.Serialize(new Money(12.50m, "SGD"), Wire.Options); // {"amount":"12.50","currency":"SGD"}
var amount = JsonSerializer.Deserialize<Money>(json, Wire.Options)!.Amount; // 12.50
```

## Integer beyond ±2^53

```csharp
public sealed record Counter(long Count);

var json = JsonSerializer.Serialize(new Counter(9007199254740993), Wire.Options); // {"count":"9007199254740993"}
var count = JsonSerializer.Deserialize<Counter>(json, Wire.Options)!.Count; // 9007199254740993
```

## Enum

```csharp
public enum Status { Pending, InProgress, Done }
public sealed record Job(Status Status);

JsonSerializer.Serialize(new Job(Status.InProgress), Wire.Options); // {"status":"in_progress"}
```

## Missing value

```csharp
public sealed record Note(string? Body);

JsonSerializer.Serialize(new Note(null), Wire.Options); // {}
```

## Binary

```csharp
public sealed record Blob(byte[] Data);

JsonSerializer.Serialize(new Blob("hi"u8.ToArray()), Wire.Options); // {"data":"aGk="}
```

## Error

```csharp
public sealed record Problem(string Type, string Title, int Status);

JsonSerializer.Serialize(
    new Problem("https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/entity_not_found", "Entity not found", 404),
    Wire.Options);
// {"type":"https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/entity_not_found","title":"Entity not found","status":404}
```

Send it with `Content-Type: application/problem+json`. In ASP.NET Core,
`TypedResults.Problem(type: ..., title: ..., statusCode: 404)` writes the same body.
