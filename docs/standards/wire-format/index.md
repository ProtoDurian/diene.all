# Wire Format

Every language reads and writes JSON exactly in this form.

| Value                | Wire form                                                                                 | Example                                                                                                             |
| -------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Keys                 | camelCase                                                                                 | `{"orderId": ...}`                                                                                                  |
| UUID                 | lowercase string; v7 for new ids                                                          | `"0190f3c2-7a4b-7c1d-9e2f-3a4b5c6d7e8f"`                                                                            |
| Instant              | UTC, exactly 3 fractional digits, `Z`                                                     | `"2024-03-15T14:30:00.000Z"`                                                                                        |
| Date                 | `YYYY-MM-DD`                                                                              | `"2024-03-15"`                                                                                                      |
| Time of day          | `HH:MM:SS`                                                                                | `"14:30:00"`                                                                                                        |
| Zoned value          | the instant + the IANA zone name, 2 fields                                                | `{"at":"2024-03-15T14:30:00.000Z","zone":"Asia/Singapore"}`                                                         |
| Duration             | ISO 8601 normal form                                                                      | `"PT2H30M"`, `"P1DT2H"`                                                                                             |
| Money / decimal      | decimal string + ISO 4217 currency; never a float                                         | `{"amount":"12.50","currency":"SGD"}`                                                                               |
| Integer beyond ±2^53 | string                                                                                    | `"9007199254740993"`                                                                                                |
| Enum                 | snake_case string                                                                         | `"in_progress"`                                                                                                     |
| Missing value        | omit the field; never `null`                                                              | `{}`                                                                                                                |
| Binary               | standard padded base64                                                                    | `"aGk="`                                                                                                            |
| Error                | RFC 9457 Problem; `type` is the full URI (lib-contracts §2.1) ending in the snake_case id | `{"type":"https://errors.atomi.cloud/docs/lapras/nitroso/zinc/api/v1/entity_not_found","title":"...","status":404}` |
