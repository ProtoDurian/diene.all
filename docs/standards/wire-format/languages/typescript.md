# Wire Format: TypeScript

These tools produce every row of [Wire Format](../index.md):

- `JSON.stringify` writes the JSON.
- Zod (`zod`) validates and parses what comes in.
- Temporal (`@js-temporal/polyfill`) holds instants, dates, times and durations.

## Keys

```typescript
JSON.stringify({ orderId }); // '{"orderId":"..."}'
const Order = z.object({ orderId: z.uuid() });
```

## UUID

```typescript
JSON.stringify({ id: Bun.randomUUIDv7() }); // lowercase v7
const Id = z.uuid().toLowerCase();
```

## Instant

```typescript
JSON.stringify({ at: instant.toString({ fractionalSecondDigits: 3 }) }); // '{"at":"2024-03-15T14:30:00.000Z"}'
const Instant = z.iso.datetime({ precision: 3 }).transform(s => Temporal.Instant.from(s));
```

## Date

```typescript
JSON.stringify({ day: day.toString() }); // '{"day":"2024-03-15"}'
const Day = z.iso.date().transform(s => Temporal.PlainDate.from(s));
```

## Time of day

```typescript
JSON.stringify({ opensAt: time.toString({ smallestUnit: 'second' }) }); // '{"opensAt":"14:30:00"}'
const TimeOfDay = z.iso.time({ precision: 0 }).transform(s => Temporal.PlainTime.from(s));
```

## Zoned value

```typescript
JSON.stringify({ at: zoned.toInstant().toString({ fractionalSecondDigits: 3 }), zone: zoned.timeZoneId });
// '{"at":"2024-03-15T14:30:00.000Z","zone":"Asia/Singapore"}'
const isZone = (zone: string) => {
  try {
    return Boolean(Temporal.Now.zonedDateTimeISO(zone));
  } catch {
    return false;
  }
};
const Zoned = z
  .object({ at: Instant, zone: z.string().refine(isZone) })
  .transform(({ at, zone }) => at.toZonedDateTimeISO(zone));
```

## Duration

```typescript
JSON.stringify({ timeout: timeout.toString() }); // '{"timeout":"PT2H30M"}', or 'P1DT2H'
const Duration = z.iso.duration().transform(s => Temporal.Duration.from(s));
```

## Money / decimal

```typescript
JSON.stringify({ amount: '12.50', currency: 'SGD' }); // never 12.5
const Money = z.object({ amount: z.string().regex(/^-?\d+(\.\d+)?$/), currency: z.string().regex(/^[A-Z]{3}$/) });
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
JSON.stringify({ status: 'in_progress' });
const Status = z.enum(['pending', 'in_progress', 'done']);
```

## Missing value

```typescript
JSON.stringify({ note: undefined }); // '{}'
const Order = z.object({ note: z.string().optional() }); // not .nullable()
```

## Binary

```typescript
JSON.stringify({ data: Buffer.from(bytes).toString('base64') }); // '{"data":"aGk="}'
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
const Problem = z.object({ type: z.url(), title: z.string(), status: z.number().int() });
```
