# class-validator → zod migration audit (C0 note)

The helium seed (`nitroso/helium src/system/loader.ts`) validated its root config
with **class-validator** + **class-transformer**. This lib migrates that contract
to **zod**. Audited for semantics zod cannot express 1:1.

## Validation rules: expressible 1:1

| helium (class-validator / class-transformer)             | zod equivalent                                                    | note                                  |
| -------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------- |
| `@IsNumber()` / `@IsString()` / `@IsBoolean()`           | `z.number()` / `z.string()` / `z.boolean()`                       | direct                                |
| `skipMissingProperties: false` (all properties required) | zod fields are required by default; opt out with `.optional()`    | direct, and more explicit             |
| nested `@ValidateNested()` + `@Type()`                   | nested `z.object({...})`                                          | direct                                |
| `@IsOptional()`                                          | `.optional()`                                                     | direct                                |
| aggregated error list (`errors.toString()`)              | `ConfigValidationError` aggregates `error.issues` per dotted path | improved (readable per-path messages) |

## Env conversion: type-directed in both, by different means

helium's `enableImplicitConversion: true` converted each env string from the
property's reflected TypeScript type (`design:type`). zod has no reflection, so
the loader walks the registry's root zod schema alongside the env path instead:
it peels `optional` / `nullable` / `default` / `prefault` / `readonly` / `catch`
/ `lazy` and takes a pipe's input side, then converts by the leaf type.

| leaf type                   | helium (class-transformer)                | this lib                                                                              |
| --------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------- |
| `string` (and string enums) | stays a string                            | stays a string (`0123`, `true`, `123456` are kept as text)                            |
| `number`                    | `Number(value)`, so `''` → 0, `0x10` → 16 | zod number parse of a decimal only; anything else stays a string and fails validation |
| `boolean`                   | `Boolean(value)`, so `'false'` → true     | `true` / `false` only (any case); anything else fails validation                      |
| `bigint`, `date`            | `design:type` constructor                 | stays a string, so `z.coerce.bigint()` / `z.coerce.date()` parse it exactly           |
| array                       | not converted from env                    | indexed keys `KEY__0`, `KEY__1`, element type applied per index                       |
| no single type (see gaps)   | not converted                             | plain scalar guess: `true`/`false`, then decimal number, else string                  |

No hand-rolled `Number()` is used anywhere; numbers go through zod.

## Gaps to record against C0 (the cross-language config contract)

These leaves have no single scalar type to direct the conversion, so an env value
gets the plain scalar guess and can differ from what helium did:

- **Unions and `z.unknown()` / `z.any()` / records**: `'0123'` into
  `z.union([z.string(), z.number()])` becomes the number `123`.
- **Plain `z.bigint()` / `z.date()`**: helium built the value from
  `design:type`; here the leaf gets the raw string, which only the coercing forms
  (`z.coerce.bigint()`, `z.coerce.date()`) accept.
- **Keys not in the registry**: no schema type exists, so the scalar guess applies
  (zod then strips the key anyway).

**Rule (stated here for every language's loader):** a config leaf that env may
override must be declared with one concrete scalar type (string, number or
boolean), or with an explicit coercing type (`z.coerce.date()`,
`z.coerce.bigint()`). Union, `unknown` and record leaves must not be set from
env. This is recorded against C0 as the one place zod does not express helium's
behaviour 1:1.
