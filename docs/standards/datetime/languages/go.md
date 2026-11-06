# Date and Time in Go

## Libraries: `time`, `civil` and `sosodev/duration`

`time.Time` is always an instant in some location, so it cannot hold "a calendar
date" or "a time of day" without inventing a zone. `cloud.google.com/go/civil`
(module `cloud.google.com/go` v0.123.0, pinned in `go.mod`) adds the wall-clock
types. Instants, durations and zones stay in the standard `time` package.
`github.com/sosodev/duration` (v1.4.0, pinned in `go.mod`) reads and writes
ISO 8601 durations, which `time` cannot.

```bash
go get cloud.google.com/go@v0.123.0
go get github.com/sosodev/duration@v1.4.0
```

```go
import (
	"time"

	"cloud.google.com/go/civil"
	"github.com/sosodev/duration"
)
```

| Concept         | Go type                                     | Wire format                                                 |
| --------------- | ------------------------------------------- | ----------------------------------------------------------- |
| Instant         | `time.Time`, normalized with `UTC()`        | `"2024-03-15T14:30:00.000Z"`                                |
| Date            | `civil.Date`                                | `"2024-03-15"`                                              |
| Time of day     | `civil.Time`                                | `"14:30:00"`                                                |
| Local date-time | `civil.DateTime` (input only, never stored) | not sent                                                    |
| Zoned value     | `time.Time` (UTC) + IANA zone `string`      | `{"at":"2024-03-15T14:30:00.000Z","zone":"Asia/Singapore"}` |
| Duration        | `time.Duration`                             | `"PT2H30M"`, `"P1DT2H"`                                     |

## Types

### Instant: `time.Time`

A point on the global timeline. Normalize with `UTC()` whenever one crosses a
boundary (storage, transport, logs).

```go
occurredAt, err := time.Parse(time.RFC3339, "2024-03-15T14:30:00Z")
if err != nil {
	return fmt.Errorf("occurred at: %w", err)
}

fromEpoch := time.UnixMilli(1710513000000).UTC()

later := occurredAt.Add(2 * time.Hour)

occurredAt.Equal(fromEpoch) // true
occurredAt.Compare(later)   // -1, 0 or +1
occurredAt.Before(later)    // true
later.Sub(occurredAt)       // 2h0m0s
```

### Date: `civil.Date`

A calendar date with no time and no zone.

```go
date, err := civil.ParseDate("2024-03-15")
if err != nil {
	return fmt.Errorf("date: %w", err)
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

### Time of Day: `civil.Time`

A wall-clock time with no date and no zone.

```go
opens, err := civil.ParseTime("09:00:00")
if err != nil {
	return fmt.Errorf("opens: %w", err)
}
closes := civil.Time{Hour: 17, Minute: 30}

opens.Before(closes) // true
opens.String()       // "09:00:00"
```

`civil.Time` prints fractional seconds when `Nanosecond` is non-zero
(`"14:30:00.000000005"`). Keep it zero for wire values: build them with
`Nanosecond: 0`, or clear the field before you send one.

`civil.Time` has no arithmetic. To add to a time of day, combine it with a date
and a zone, and do the work on the resulting instant.

### Local Date-Time: `civil.DateTime`

A date and a time with no zone. It is an input step only: resolve it against a
zone straight away and keep the instant.

```go
startsAt, err := civil.ParseDateTime("2024-03-15T22:30:00")
if err != nil {
	return fmt.Errorf("starts at: %w", err)
}

combined := civil.DateTime{Date: date, Time: opens}
```

### Zoned Value: Instant + Zone Name

Go has no zoned type of its own. Store two fields: the instant, as a UTC
`time.Time`, and the IANA zone name. Never store a `civil.DateTime` with a
zone: the instant is what sorts and compares.

```go
// lib/meeting/structures.go
type Meeting struct {
	At   time.Time
	Zone string
}
```

```go
// lib/meeting/scheduler.go
var ErrUnknownZone = errors.New("unknown time zone")

type Scheduler struct{}

func (Scheduler) Schedule(local civil.DateTime, zone string) (Meeting, error) {
	loc, err := time.LoadLocation(zone)
	if err != nil {
		return Meeting{}, fmt.Errorf("%w %q: %w", ErrUnknownZone, zone, err)
	}
	return Meeting{At: local.In(loc).UTC(), Zone: zone}, nil
}

func (Scheduler) WallClock(meeting Meeting) (civil.DateTime, error) {
	loc, err := time.LoadLocation(meeting.Zone)
	if err != nil {
		return civil.DateTime{}, fmt.Errorf("%w %q: %w", ErrUnknownZone, meeting.Zone, err)
	}
	return civil.DateTimeOf(meeting.At.In(loc)), nil
}
```

`22:30` in `Asia/Singapore` stores as `At = 2024-03-15T14:30:00.000Z`,
`Zone = "Asia/Singapore"`.

`In` panics on a nil location, so always check the error from `LoadLocation`.
Zone data comes from the operating system. If the runtime image has no
`/usr/share/zoneinfo`, embed it once in the composition root:

```go
// cmd/go-base/main.go
import _ "time/tzdata"
```

### Duration: `time.Duration`

The domain uses `time.Duration`. ISO 8601 text appears only at the edge.

```go
timeout := 30 * time.Second
window := 2*time.Hour + 30*time.Minute

deadline := clock.Now().Add(timeout)
elapsed := end.Sub(start)
window.Minutes() // 150

duration.Format(window)         // "PT2H30M"
duration.Format(26 * time.Hour) // "P1DT2H"

parsed, err := duration.Parse("P1DT2H")
if err != nil {
	return fmt.Errorf("duration: %w", err)
}
parsed.String()         // "P1DT2H"
parsed.ToTimeDuration() // 26h0m0s
```

`duration.Format` counts a day as 24 hours, and folds 7 days or more into weeks
and months (`P1W1D`). For calendar spans longer than a few days, keep the
parsed `*duration.Duration` instead of round-tripping it through
`time.Duration`.

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

Take "today" from the user's zone, not the server's:

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

loc, err := time.LoadLocation(user.Timezone)
if err != nil {
	return fmt.Errorf("user zone: %w", err)
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

Every value crosses the wire as
[Wire Format: Go](../../wire-format/languages/go.md) shows. `civil.Date`,
`civil.Time` and `duration.Duration` already encode correctly. `time.Time` does
not: its default encoding is RFC 3339 with up to nine fractional digits and
whatever offset it holds. Adapters send instants through a small type that
always writes UTC with exactly three fractional digits.

```go
// adapters/api/instant.go
const instantLayout = "2006-01-02T15:04:05.000Z07:00"

type Instant time.Time

func (instant Instant) MarshalJSON() ([]byte, error) {
	return json.Marshal(time.Time(instant).UTC().Format(instantLayout))
}

func (instant *Instant) UnmarshalJSON(data []byte) error {
	var raw string
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("instant: %w", err)
	}
	parsed, err := time.Parse(instantLayout, raw)
	if err != nil {
		return fmt.Errorf("instant %q: %w", raw, err)
	}
	*instant = Instant(parsed.UTC())
	return nil
}
```

The layout demands exactly three fractional digits on input, so
`"2024-03-15T14:30:00Z"` is rejected. An offset such as `+08:00` is accepted
and normalized to UTC; output always ends in `Z`.

```go
// adapters/api/event/res.go
type EventRes struct {
	OccurredAt api.Instant       `json:"occurredAt"`
	Day        civil.Date        `json:"day"`
	Timeout    duration.Duration `json:"timeout"`
}

func (Mapper) ToRes(event Event) EventRes {
	return EventRes{
		OccurredAt: api.Instant(event.OccurredAt),
		Day:        event.Day,
		Timeout:    *duration.FromTimeDuration(event.Timeout),
	}
}

// {"occurredAt":"2024-03-15T14:30:00.000Z","day":"2024-03-15","timeout":"PT2H30M"}
```

A `duration.Duration` field round-trips on its own:

```go
var req struct {
	Length duration.Duration `json:"length"`
}
if err := json.Unmarshal([]byte(`{"length":"PT2H30M"}`), &req); err != nil {
	return fmt.Errorf("decode: %w", err)
}
req.Length.ToTimeDuration() // 2h30m0s
```
