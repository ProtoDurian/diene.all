# Date and Time in Go

## Library: `cloud.google.com/go/civil`

`time.Time` is always an instant in some location, so it cannot hold "a calendar
date" or "a time of day" without inventing a zone. `civil` adds the three
wall-clock types; instants, durations and zones stay in the standard `time`
package.

```bash
go get cloud.google.com/go/civil
```

```go
import (
	"time"

	"cloud.google.com/go/civil"
)
```

| Concept         | Go type                                   | Wire format                      |
| --------------- | ----------------------------------------- | -------------------------------- |
| Instant         | `time.Time`, normalized with `UTC()`      | RFC 3339 (`time.RFC3339Nano`)    |
| Date            | `civil.Date`                              | `YYYY-MM-DD`                     |
| Time            | `civil.Time`                              | `HH:MM:SS`                       |
| Local date-time | `civil.DateTime`                          | `YYYY-MM-DDTHH:MM:SS`            |
| Timezone        | `*time.Location` from `time.LoadLocation` | IANA id, e.g. `America/New_York` |
| Duration        | `time.Duration`                           | ISO 8601, e.g. `PT9000S`         |

## Types

### Instant: `time.Time`

A point on the global timeline. Normalize with `UTC()` whenever one crosses a
boundary (storage, transport, logs).

```go
occurredAt, err := time.Parse(time.RFC3339, "2024-03-15T14:30:00Z")
if err != nil {
	return err
}

fromEpoch := time.UnixMilli(1710513000000).UTC()

occurredAt.UTC().Format(time.RFC3339Nano) // "2024-03-15T14:30:00Z"

later := occurredAt.Add(2 * time.Hour)

occurredAt.Equal(fromEpoch)  // true
occurredAt.Compare(later)    // -1, 0 or +1
occurredAt.Before(later)     // true
later.Sub(occurredAt)        // 2h0m0s
```

### Date: `civil.Date`

A calendar date with no time and no zone.

```go
date, err := civil.ParseDate("2024-03-15")
if err != nil {
	return err
}
literal := civil.Date{Year: 2024, Month: time.March, Day: 15}

date.Year      // 2024
date.Month     // time.March
date.Day       // 15
date.Weekday() // time.Friday

tomorrow := date.AddDays(1)
lastYear := date.AddYears(-1)

other := civil.Date{Year: 2024, Month: time.April, Day: 20}
other.DaysSince(date) // 36
date.Compare(literal) // 0
```

A struct literal is not checked. Call `IsValid()` on any `civil` value you did
not get from a `Parse...` function.

```go
civil.Date{Year: 2024, Month: time.February, Day: 30}.IsValid() // false
```

### Time: `civil.Time`

A wall-clock time with no date and no zone.

```go
opens, err := civil.ParseTime("09:00:00")
if err != nil {
	return err
}
closes := civil.Time{Hour: 17, Minute: 30}

opens.Before(closes) // true
opens.String()       // "09:00:00"
```

`civil.Time` has no arithmetic. When you need to add to a time of day, combine
it with a date and do the work on a `civil.DateTime` or in a zone.

### Local date-time: `civil.DateTime`

A date and a time with no zone. Store it only next to the zone that gives it
meaning.

```go
startsAt, err := civil.ParseDateTime("2024-03-15T14:30:00")
if err != nil {
	return err
}

combined := civil.DateTime{Date: date, Time: opens}

startsAt.Date // civil.Date{Year: 2024, Month: time.March, Day: 15}
startsAt.Time // civil.Time{Hour: 14, Minute: 30}
```

### Zoned date-time: `civil.DateTime` + `*time.Location`

Go has no zoned type of its own. Keep the local value and the IANA id as two
fields, and resolve them into an instant with `In`.

```go
type Meeting struct {
	StartsAt civil.DateTime
	Zone     string
}

loc, err := time.LoadLocation(meeting.Zone)
if err != nil {
	return err
}

instant := meeting.StartsAt.In(loc).UTC()

tokyo, err := time.LoadLocation("Asia/Tokyo")
if err != nil {
	return err
}
civil.DateTimeOf(instant.In(tokyo)) // the same moment on a Tokyo wall clock
```

`In` panics on a nil location, so always check the error from `LoadLocation`.
Zone data comes from the operating system. If the runtime image has no
`/usr/share/zoneinfo`, embed it once in the composition root:

```go
// cmd/go-base/main.go
import _ "time/tzdata"
```

### Duration: `time.Duration`

```go
timeout := 30 * time.Second
window := 2*time.Hour + 30*time.Minute

parsed, err := time.ParseDuration("2h30m")
if err != nil {
	return err
}

deadline := clock.Now().Add(timeout)
elapsed := end.Sub(start)
window.Minutes() // 150
```

Never pass a bare integer for a duration: `Sleep(5)` is five nanoseconds.

## Inject the Clock

Domain code never calls `time.Now`. It asks an injected clock, so tests can
pin the instant.

```go
// lib/note/clock.go
type Clock interface {
	Now() time.Time
}

type Stamper struct {
	clock Clock
}

func NewStamper(clock Clock) Stamper {
	return Stamper{clock: clock}
}

func (stamper Stamper) Stamp(body string) StampedNote {
	return StampedNote{Body: body, CreatedAt: stamper.clock.Now().UTC()}
}
```

```go
// adapters/clock/system.go
type System struct{}

func (System) Now() time.Time {
	return time.Now().UTC()
}
```

```go
// tests/unit/note/stamper_test.go
type FixedClock struct {
	At time.Time
}

func (clock FixedClock) Now() time.Time {
	return clock.At
}
```

## Best Practices

### Use `civil.Date` for Birthdays

```go
// WRONG - midnight UTC is a different calendar day west of Greenwich
birthday := time.Date(1990, time.March, 15, 0, 0, 0, 0, time.UTC)

// RIGHT - a date is a date
birthday := civil.Date{Year: 1990, Month: time.March, Day: 15}
```

Work out the age from dates only. Take "today" from the user's zone, not the
server's:

```go
today := civil.DateOf(clock.Now().In(userLoc))

age := today.Year - birthday.Year
if today.Month < birthday.Month || (today.Month == birthday.Month && today.Day < birthday.Day) {
	age--
}
```

### Store Instants, Display Zoned

```go
createdAt := clock.Now().UTC()
row := NoteRow{CreatedAt: createdAt.Format(time.RFC3339Nano)}

loc, err := time.LoadLocation(user.Timezone)
if err != nil {
	return err
}
shown := createdAt.In(loc).Format("Mon, 02 Jan 2006 15:04 MST")
```

### Compare Instants with `Equal`, Not `==`

`==` compares the location pointer and the monotonic clock reading as well as
the instant.

```go
// WRONG - false for the same instant in two locations
same := a == b

// RIGHT
same := a.Equal(b)
```

### Never Use the Machine's Zone as Domain State

```go
// WRONG - the result depends on the TZ of whichever host runs it
startsAt, err := time.ParseInLocation("2006-01-02 15:04", raw, time.Local)

// RIGHT - the zone is data
startsAt, err := time.ParseInLocation("2006-01-02 15:04", raw, meetingLoc)
```

`time.Parse` with a layout that has no zone returns UTC, not local time. Use
`time.ParseInLocation` with an explicit location when the input is a wall-clock
value.

### Month Arithmetic Overflows

`AddDate` and `civil.Date.AddMonths` normalize out-of-range days, so
31 January plus one month is 2 March (or 3 March in a non-leap year). When you
mean "same day next month, clamped to the last day", write that rule as a
domain method and test it.

## JSON Serialization

Every `civil` type implements `encoding.TextMarshaler`, so it encodes as the
wire formats above. `time.Time` encodes as RFC 3339 with whatever offset it
holds, so convert to UTC in the adapter mapper. Go has no ISO 8601 duration
codec: the adapter owns a small named type.

```go
// adapters/api/res.go
type EventRes struct {
	OccurredAt time.Time   `json:"occurredAt"`
	Day        civil.Date  `json:"day"`
	Timeout    ISODuration `json:"timeout"`
}

func NewEventRes(event Event) EventRes {
	return EventRes{
		OccurredAt: event.OccurredAt.UTC(),
		Day:        event.Day,
		Timeout:    ISODuration(event.Timeout),
	}
}
```

```go
// adapters/api/duration.go
type ISODuration time.Duration

func (duration ISODuration) MarshalText() ([]byte, error) {
	seconds := strconv.FormatFloat(time.Duration(duration).Seconds(), 'f', -1, 64)
	return []byte("PT" + seconds + "S"), nil
}

func (duration *ISODuration) UnmarshalText(text []byte) error {
	seconds, ok := strings.CutPrefix(string(text), "PT")
	seconds, hasSuffix := strings.CutSuffix(seconds, "S")
	if !ok || !hasSuffix {
		return fmt.Errorf("duration %q: want PT<seconds>S", text)
	}
	parsed, err := time.ParseDuration(seconds + "s")
	if err != nil {
		return fmt.Errorf("duration %q: %w", text, err)
	}
	*duration = ISODuration(parsed)
	return nil
}
```

This codec only reads and writes the seconds form (`PT9000S`). If you must
accept full ISO 8601 durations from outside (`P1DT2H`), that parser is its own
package with its own tests.
