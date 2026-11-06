# Wire Format: TypeScript

These tools produce every row of [Wire Format](../index.md):

- `JSON.stringify` writes the JSON.
- Zod (`zod`) validates and parses what comes in.
- Temporal (`@js-temporal/polyfill`) holds instants, dates, times and durations.

## Keys

```typescript
JSON.stringify({ orderId }); // '{"orderId":"..."}'
```

## UUID

```typescript
const id = Bun.randomUUIDv7(); // lowercase v7
const Id = z.uuid().toLowerCase();
```

## Instant

```typescript
instant.toString({ fractionalSecondDigits: 3 }); // '2024-03-15T14:30:00.000Z'
const Instant = z.iso.datetime({ precision: 3 }).transform(s => Temporal.Instant.from(s));
```

## Date

```typescript
Temporal.PlainDate.from('2024-03-15').toString(); // '2024-03-15'
const Day = z.iso.date().transform(s => Temporal.PlainDate.from(s));
```

## Time of day

```typescript
Temporal.PlainTime.from('14:30').toString({ smallestUnit: 'second' }); // '14:30:00'
const TimeOfDay = z.iso.time({ precision: 0 }).transform(s => Temporal.PlainTime.from(s));
```

## Zoned value

```typescript
JSON.stringify({ at: zoned.toInstant().toString({ fractionalSecondDigits: 3 }), zone: zoned.timeZoneId });
// '{"at":"2024-03-15T14:30:00.000Z","zone":"Asia/Singapore"}'
Temporal.Instant.from(at).toZonedDateTimeISO(zone); // read it back
```

## Duration

```typescript
Temporal.Duration.from({ hours: 2, minutes: 30 }).toString(); // 'PT2H30M'
Temporal.Duration.from({ days: 1, hours: 2 }).toString(); // 'P1DT2H'
```

## Money / decimal

```typescript
const Money = z.object({ amount: z.string().regex(/^-?\d+(\.\d+)?$/), currency: z.string().regex(/^[A-Z]{3}$/) });
JSON.stringify({ amount: '12.50', currency: 'SGD' }); // never 12.5
```

## Integer beyond ±2^53

```typescript
JSON.stringify({ count: count.toString() }); // '{"count":"9007199254740993"}'
const Count = z
  .string()
  .regex(/^-?\d+$/)
  .transform(BigInt);
```

## Enum

```typescript
const Status = z.enum(['pending', 'in_progress', 'done']);
```

## Missing value

```typescript
const Order = z.object({ note: z.string().optional() }); // not .nullable()
JSON.stringify({ note: undefined }); // '{}'
```

## Binary

```typescript
Buffer.from(bytes).toString('base64'); // 'aGk='
const Bytes = z.base64().transform(s => Buffer.from(s, 'base64'));
```

## Error

```typescript
Response.json(
  {
    type: 'https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/entity_not_found',
    title: 'Entity not found',
    status: 404,
  },
  { status: 404, headers: { 'Content-Type': 'application/problem+json' } },
);
```
