# Validation in Go

## Library: `go-playground/validator`

`github.com/go-playground/validator/v10` (v10.30.6) checks
request shape from struct tags. It validates the adapter's request types only.
Domain rules stay in domain constructors that return `(T, error)`.

```bash
go get github.com/go-playground/validator/v10@v10.30.6
```

```go
import "github.com/go-playground/validator/v10"
```

## One Shared Validator

`*validator.Validate` caches struct metadata and is safe for concurrent use.
Build it once in the composition root and inject it. Never call
`validator.New()` per request.

```go
// adapters/api/validate.go
func NewValidate() (*validator.Validate, error) {
	validate := validator.New(validator.WithRequiredStructEnabled())
	validate.RegisterTagNameFunc(FieldNamer{}.JSON)
	if err := validate.RegisterValidation("decimal", NewDecimalRule().Check); err != nil {
		return nil, fmt.Errorf("register decimal rule: %w", err)
	}
	return validate, nil
}
```

```go
// adapters/api/names.go
type FieldNamer struct{}

func (FieldNamer) JSON(field reflect.StructField) string {
	name, _, _ := strings.Cut(field.Tag.Get("json"), ",")
	if name == "-" {
		return ""
	}
	return name
}
```

`RegisterTagNameFunc` makes errors name the wire field (`items[0].quantity`),
not the Go field (`Items[0].Quantity`).

```go
// cmd/go-base/main.go
validate, err := api.NewValidate()
if err != nil {
	return fmt.Errorf("build validator: %w", err)
}
checker := api.NewRequestValidator(validate, api.Messages{})
orders := orderapi.NewController(checker, orderService)
```

## Request Types

The request type mirrors the wire. Tags sit here, never on domain structs.
Pointer fields tell a missing field apart from an empty one.

```go
// adapters/api/order/req.go
type CreateOrderReq struct {
	Items           []ItemReq   `json:"items" validate:"required,min=1,dive"`
	ShippingAddress *AddressReq `json:"shippingAddress" validate:"required"`
	Email           *string     `json:"email" validate:"required,email"`
	Note            *string     `json:"note,omitempty" validate:"omitempty,max=500"`
}

type ItemReq struct {
	ProductID string `json:"productId" validate:"required,uuid,lowercase"`
	Quantity  int    `json:"quantity" validate:"gt=0"`
}

type AddressReq struct {
	Street  string `json:"street" validate:"required"`
	City    string `json:"city" validate:"required"`
	ZipCode string `json:"zipCode" validate:"required,len=5,numeric"`
}
```

`dive` checks every element of a slice or map. A pointer to a struct is
followed and checked; `required` on it rejects `nil`.

### Common Tags

| Tag                                  | Checks                                     |
| ------------------------------------ | ------------------------------------------ |
| `required`                           | not the zero value; a pointer is not `nil` |
| `omitempty`                          | skip the remaining rules when empty        |
| `min=2`, `max=100`, `len=5`          | string length, slice length, or number     |
| `gt=0`, `gte=0`, `lt=100`, `lte=100` | number bounds                              |
| `email`, `url`, `uuid`, `uuid7`      | string formats                             |
| `lowercase`, `numeric`, `alphanum`   | character classes                          |
| `oneof=pending in_progress done`     | one of a fixed set (enums)                 |
| `iso4217`, `timezone`                | currency code, IANA zone name              |
| `eqfield=Password`, `gtfield=Start`  | compare with a sibling field (Go name)     |
| `dive`                               | apply the following tags to each element   |

### Cross-Field Rules

```go
type RegistrationReq struct {
	Password     string `json:"password" validate:"required,min=8"`
	Confirmation string `json:"confirmation" validate:"required,eqfield=Password"`
}
```

Field-comparison tags take the Go field name, not the JSON name.

### Custom Rules

A custom tag is an exported method on a stateless struct, registered once in
`NewValidate`.

```go
// adapters/api/decimal.go
type DecimalRule struct {
	pattern *regexp.Regexp
}

func NewDecimalRule() DecimalRule {
	return DecimalRule{pattern: regexp.MustCompile(`^-?[0-9]+(\.[0-9]+)?$`)}
}

func (rule DecimalRule) Check(field validator.FieldLevel) bool {
	return rule.pattern.MatchString(field.Field().String())
}
```

```go
type MoneyReq struct {
	Amount   string `json:"amount" validate:"required,decimal"`
	Currency string `json:"currency" validate:"required,iso4217"`
}
```

### Single Values

Query parameters and path values have no struct. Use `Var`:

```go
if err := validate.Var(limit, "min=1,max=100"); err != nil {
	return Page{}, fmt.Errorf("limit: %w", err)
}
```

## Errors as Values

`Struct` returns `validator.ValidationErrors` for bad input and
`*validator.InvalidValidationError` when you passed something it cannot check
(a nil or non-struct value): that one is a programming bug. The request
validator turns the first into a typed error the caller can match.

```go
// adapters/api/validation.go
var ErrInvalidRequest = errors.New("invalid request")

type InvalidRequestError struct {
	Fields map[string][]string
}

func (*InvalidRequestError) Error() string {
	return ErrInvalidRequest.Error()
}

func (*InvalidRequestError) Unwrap() error {
	return ErrInvalidRequest
}

type RequestValidator struct {
	validate *validator.Validate
	messages Messages
}

func NewRequestValidator(validate *validator.Validate, messages Messages) RequestValidator {
	return RequestValidator{validate: validate, messages: messages}
}

func (checker RequestValidator) Check(ctx context.Context, req any) error {
	err := checker.validate.StructCtx(ctx, req)
	var failures validator.ValidationErrors
	if !errors.As(err, &failures) {
		return err
	}
	fields := make(map[string][]string, len(failures))
	for _, failure := range failures {
		_, path, _ := strings.Cut(failure.Namespace(), ".")
		fields[path] = append(fields[path], checker.messages.For(failure))
	}
	return &InvalidRequestError{Fields: fields}
}
```

`Namespace()` starts with the Go type name (`CreateOrderReq.items[0].quantity`);
`strings.Cut` drops it.

```go
// adapters/api/messages.go
type Messages struct{}

func (Messages) For(failure validator.FieldError) string {
	switch failure.Tag() {
	case "required":
		return "Is required"
	case "email":
		return "Must be a valid email address"
	case "min":
		return "Must be at least " + failure.Param()
	case "max":
		return "Must be at most " + failure.Param()
	case "gt":
		return "Must be greater than " + failure.Param()
	case "oneof":
		return "Must be one of: " + failure.Param()
	default:
		return "Is invalid"
	}
}
```

Never echo the rejected value: it may be a password or a token.

## Validation at Boundaries

| Layer   | Checks                                       | Fails with                    | Status |
| ------- | -------------------------------------------- | ----------------------------- | ------ |
| Adapter | JSON syntax, struct tags                     | `*api.InvalidRequestError`    | 400    |
| Domain  | invariants: totals, status moves, date order | a sentinel domain error, `%w` | 422    |

### Shape in the Adapter

```go
// adapters/api/order/controller.go
func (controller Controller) Create(writer http.ResponseWriter, request *http.Request) {
	var req CreateOrderReq
	if err := json.NewDecoder(http.MaxBytesReader(writer, request.Body, 64<<10)).Decode(&req); err != nil {
		controller.problems.Write(writer, err)
		return
	}
	if err := controller.checker.Check(request.Context(), req); err != nil {
		controller.problems.Write(writer, err)
		return
	}

	draft, err := controller.mapper.ToDomain(req)
	if err != nil {
		controller.problems.Write(writer, err)
		return
	}

	created, err := controller.service.Place(request.Context(), draft)
	if err != nil {
		controller.problems.Write(writer, err)
		return
	}
	controller.responses.Write(writer, http.StatusCreated, controller.mapper.ToRes(created))
}
```

The problem writer picks the status with `errors.As` and `errors.Is`, so the
controller never decides it inline. An invalid request becomes a 400 Problem:

```json
{
  "type": "https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/validation_error",
  "title": "The request is invalid",
  "status": 400,
  "errors": {
    "email": ["Must be a valid email address"],
    "items[0].quantity": ["Must be greater than 0"]
  }
}
```

### Invariants in the Domain

The validator does not run in `lib/`. A domain type guards its own rules in a
constructor that returns `(T, error)` and wraps a sentinel with `%w`.

```go
// lib/order/total.go
var ErrNegativeTotal = errors.New("order total is negative")

type Total struct {
	minorUnits int64
	currency   string
}

func NewTotal(minorUnits int64, currency string) (Total, error) {
	if minorUnits < 0 {
		return Total{}, fmt.Errorf("%w: %d %s", ErrNegativeTotal, minorUnits, currency)
	}
	return Total{minorUnits: minorUnits, currency: currency}, nil
}
```

The problem writer maps `errors.Is(err, order.ErrNegativeTotal)` to a 422.
The domain service takes the parsed type, so it cannot receive an unchecked
value:

```go
// WRONG - every caller can pass anything
func (service Service) Place(ctx context.Context, items []ItemReq) (Order, error)

// RIGHT - holding a Draft is the proof it was checked
func (service Service) Place(ctx context.Context, draft Draft) (Order, error)
```

## Best Practices

### Return Errors, Never Panic

```go
// WRONG - a bad request crashes the process
if err := validate.Struct(req); err != nil {
	panic(err)
}

// RIGHT - the caller decides
if err := checker.Check(ctx, req); err != nil {
	return Draft{}, err
}
```

### Match Errors by Type, Not Text

```go
// WRONG
isInvalid := strings.Contains(err.Error(), "invalid request")

// RIGHT
var invalid *api.InvalidRequestError
isInvalid := errors.As(err, &invalid)
```

### Do

- Build one `*validator.Validate` in `cmd/<name>` and inject it.
- Put `validate` tags on request types in `adapters/`.
- Register every custom tag in `NewValidate`, and check its error.
- Parse into a domain type right after the tag check passes.

### Don't

- Put `validate` tags on `lib/` structs.
- Check the same rule in a tag and in a domain constructor.
- Rely on `required` for an `int` or `bool` that may legitimately be zero; use
  a pointer.
- Test that `email` or `min` work. Test your custom rules and your mapping.
