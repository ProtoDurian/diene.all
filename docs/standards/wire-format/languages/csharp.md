# Wire Format: C#/.NET

`System.Text.Json` produces every row of [Wire Format](../index.md) with one
`JsonSerializerOptions`. Build it once and pass it to every `JsonSerializer` call
(or to `ConfigureHttpJsonOptions` in ASP.NET Core).

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
            new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower),
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
        DateTimeOffset.ParseExact(reader.GetString()!, Format, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.UtcDateTime.ToString(Format, CultureInfo.InvariantCulture));
}

public sealed class DurationConverter : JsonConverter<TimeSpan>
{
    public override TimeSpan Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
        XmlConvert.ToTimeSpan(reader.GetString()!);

    public override void Write(Utf8JsonWriter writer, TimeSpan value, JsonSerializerOptions options) =>
        writer.WriteStringValue(XmlConvert.ToString(value));
}

public sealed class DecimalStringConverter : JsonConverter<decimal>
{
    public override decimal Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
        decimal.Parse(reader.GetString()!, NumberStyles.Number, CultureInfo.InvariantCulture);

    public override void Write(Utf8JsonWriter writer, decimal value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString(CultureInfo.InvariantCulture));
}

public sealed class Int64StringConverter : JsonConverter<long>
{
    public override long Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
        long.Parse(reader.GetString()!, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);

    public override void Write(Utf8JsonWriter writer, long value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToString(CultureInfo.InvariantCulture));
}
```

The defaults that need a converter: `DateTimeOffset` writes `+00:00` and up to 7
fractional digits, `TimeSpan` writes `02:30:00`, and `decimal` and `long` write
JSON numbers that lose precision in JavaScript readers. Every `long` field is a
string, so its wire type never depends on its value; use `int` for counts that
fit in a JSON number.

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
var at = JsonSerializer.Deserialize<Created>(json, Wire.Options)!.At; // 2024-03-15 14:30:00 +00:00
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

Keep `TimeOnly` values at whole seconds; a fraction would be written too.

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
var timeout = JsonSerializer.Deserialize<Retry>("""{"timeout":"P1DT2H"}""", Wire.Options)!.Timeout; // 1.02:00:00
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
