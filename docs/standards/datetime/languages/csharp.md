# Date and time in C#/.NET

Use the .NET built-in types that encode the intended semantic directly:

- `DateOnly` for calendar dates.
- `TimeOnly` for wall-clock times without a date.
- `DateTimeOffset` for instants and timestamps.
- `TimeSpan` for durations.
- `TimeZoneInfo` with IANA zone identifiers for timezone conversion.

```csharp
var createdAt = DateTimeOffset.UtcNow;
var billingDate = new DateOnly(2026, 7, 18);
var retryAfter = TimeSpan.FromMinutes(5);
var singapore = TimeZoneInfo.FindSystemTimeZoneById("Asia/Singapore");
var localCreatedAt = TimeZoneInfo.ConvertTime(createdAt, singapore);
```

Persist instants as UTC. Do not use local or `Unspecified` `DateTime` values for
wire contracts. On the wire an instant is UTC with exactly 3 fractional digits and
`Z`, a duration is ISO 8601 (`PT5M`), and a zoned value is the instant plus the
IANA zone name as two fields. [Wire Format: C#/.NET](../../wire-format/languages/csharp.md)
shows the `System.Text.Json` options that write each of them.
