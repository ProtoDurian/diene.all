# Wire Format: Go

These tools produce every row of [Wire Format](../index.md):

- `encoding/json` writes and reads the JSON, driven by `json` struct tags.
- `github.com/go-playground/validator/v10` (v10.30.6) checks what comes in.
- `time`, `cloud.google.com/go/civil` and `github.com/sosodev/duration`
  (v1.4.0) hold instants, dates, times of day and durations.

Wire types live in `adapters/`. Domain structs in `lib/` carry no `json` tags.

## Keys

Every field gets an explicit camelCase `json` tag. Without one, Go writes the
field name as is (`OrderID`).

```go
type OrderRes struct {
	OrderID string `json:"orderId"`
}

// {"orderId":"..."}
```

## UUID

Hold ids as lowercase strings. New ids are v7, from `github.com/google/uuid`
(v1.6.0; only an indirect dependency in this base, so `go get` it before you
import it). `uuid.UUID.String()` is lowercase.

```go
id, err := uuid.NewV7()
if err != nil {
	return Order{}, fmt.Errorf("new order id: %w", err)
}
res := OrderRes{OrderID: id.String()} // "0190f3c2-7a4b-7c1d-9e2f-3a4b5c6d7e8f"

type GetOrderReq struct {
	OrderID string `json:"orderId" validate:"required,uuid,lowercase"`
}
```

## Instant

`time.Time` encodes with up to nine fractional digits and its own offset. Use
the adapter's `Instant` type from
[Date and Time in Go](../../datetime/languages/go.md), which always writes UTC
with exactly three digits.

```go
type EventRes struct {
	At api.Instant `json:"at"`
}

// {"at":"2024-03-15T14:30:00.000Z"}
```

## Date

```go
type EventRes struct {
	Day civil.Date `json:"day"`
}

// {"day":"2024-03-15"}
```

## Time of Day

```go
type StoreRes struct {
	OpensAt civil.Time `json:"opensAt"`
}

// {"opensAt":"14:30:00"}
```

`civil.Time` adds fractional seconds when `Nanosecond` is non-zero. Keep it
zero.

## Zoned Value

Two fields: the instant and the IANA zone name.

```go
type MeetingReq struct {
	At   api.Instant `json:"at"`
	Zone string      `json:"zone" validate:"required,timezone"`
}

// {"at":"2024-03-15T14:30:00.000Z","zone":"Asia/Singapore"}
```

## Duration

`duration.Duration` implements `MarshalJSON` and `UnmarshalJSON`.

```go
type JobRes struct {
	Timeout duration.Duration `json:"timeout"`
}

res := JobRes{Timeout: *duration.FromTimeDuration(2*time.Hour + 30*time.Minute)}
// {"timeout":"PT2H30M"}; 26 hours writes "P1DT2H"
```

## Money / Decimal

A decimal string plus an ISO 4217 code. Never `float64`.

```go
type MoneyReq struct {
	Amount   string `json:"amount" validate:"required,decimal"`
	Currency string `json:"currency" validate:"required,iso4217"`
}

// {"amount":"12.50","currency":"SGD"}
```

`decimal` is the custom rule registered in
[Validation in Go](../../validation/languages/go.md).

## Integer Beyond ±2^53

The `,string` option writes and reads an `int64` as a JSON string.

```go
type CounterRes struct {
	Count int64 `json:"count,string"`
}

// {"count":"9007199254740993"}
```

## Enum

A named string type with snake_case constants.

```go
type Status string

const (
	StatusPending    Status = "pending"
	StatusInProgress Status = "in_progress"
	StatusDone       Status = "done"
)

type TaskReq struct {
	Status Status `json:"status" validate:"required,oneof=pending in_progress done"`
}

// {"status":"in_progress"}
```

## Missing Value

Omit the field; never send `null`. A nil pointer, nil slice or nil map encodes
as `null` unless the tag says otherwise.

```go
type NoteRes struct {
	Note     *string     `json:"note,omitempty"`
	Tags     []string    `json:"tags,omitempty"`
	Birthday civil.Date  `json:"birthday,omitzero"`
	SeenAt   api.Instant `json:"seenAt,omitzero"`
}

// {} when every field is empty
```

`omitempty` does not skip struct values. Use `omitzero` for `civil.Date`,
`civil.Time`, `api.Instant` and other struct types.

## Binary

`[]byte` encodes as standard padded base64.

```go
type BlobRes struct {
	Data []byte `json:"data"`
}

// {"data":"aGk="} for []byte("hi")
```

## Error

An RFC 9457 Problem, sent as `application/problem+json`. `type` is the full
URI ending in the snake_case error id.

```go
type Problem struct {
	Type     string              `json:"type"`
	Title    string              `json:"title"`
	Status   int                 `json:"status"`
	Detail   string              `json:"detail,omitempty"`
	Instance string              `json:"instance,omitempty"`
	Errors   map[string][]string `json:"errors,omitempty"`
}

writer.Header().Set("Content-Type", "application/problem+json")
writer.WriteHeader(http.StatusNotFound)
err := json.NewEncoder(writer).Encode(Problem{
	Type:   "https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/entity_not_found",
	Title:  "Entity not found",
	Status: http.StatusNotFound,
})
```
