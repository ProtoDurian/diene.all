import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^\d{2}:\d{2}:\d{2}$/;
const INSTANT_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/;
const OFFSET_ZONE_PATTERN = /^[+-]\d{2}:\d{2}$/;

type WireForm = 'date' | 'time' | 'datetime' | 'duration' | 'timezone';

declare const wireTimeZoneBrand: unique symbol;
type WireTimeZone = string & { readonly [wireTimeZoneBrand]: 'WireTimeZone' };

class WireDateError extends RangeError {
  constructor(
    readonly form: WireForm,
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = 'WireDateError';
  }
}

class WireDateCodec {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  parseDate(input: string): Result<Temporal.PlainDate, WireDateError> {
    if (!DATE_PATTERN.test(input)) {
      return this.fail('date', `wire date must be canonical YYYY-MM-DD, received "${input}"`);
    }
    return this.attempt('date', `wire date "${input}" is not a valid calendar date`, () =>
      Temporal.PlainDate.from(input, { overflow: 'reject' }),
    );
  }

  formatDate(date: Temporal.PlainDate): Result<string, WireDateError> {
    const formatted = date.toString();
    if (!DATE_PATTERN.test(formatted)) {
      return this.fail('date', 'wire date domain value cannot be represented as canonical YYYY-MM-DD');
    }
    return Ok(formatted);
  }

  parseTime(input: string): Result<Temporal.PlainTime, WireDateError> {
    if (!TIME_PATTERN.test(input)) {
      return this.fail(
        'time',
        `wire time must be canonical HH:mm:ss with seconds and no fraction or offset, received "${input}"`,
      );
    }
    return this.attempt('time', `wire time "${input}" is not a valid time of day`, () =>
      Temporal.PlainTime.from(input, { overflow: 'reject' }),
    );
  }

  formatTime(time: Temporal.PlainTime): Result<string, WireDateError> {
    if (time.millisecond !== 0 || time.microsecond !== 0 || time.nanosecond !== 0) {
      return this.fail('time', 'wire time domain value must have whole-second precision');
    }
    return Ok(time.toString({ smallestUnit: 'second' }));
  }

  parseDateTime(input: string): Result<Temporal.Instant, WireDateError> {
    if (!INSTANT_PATTERN.test(input)) {
      return this.fail(
        'datetime',
        `wire datetime must be a canonical RFC 3339 UTC instant (YYYY-MM-DDTHH:mm:ssZ), received "${input}"`,
      );
    }
    return this.attempt('datetime', `wire datetime "${input}" is not a valid instant`, () =>
      Temporal.Instant.from(input),
    ).andThen(instant =>
      instant.toString() === input
        ? Ok(instant)
        : this.fail('datetime', `wire datetime must use canonical fractional precision, received "${input}"`),
    );
  }

  formatDateTime(instant: Temporal.Instant): Result<string, WireDateError> {
    const formatted = instant.toString();
    if (!INSTANT_PATTERN.test(formatted)) {
      return this.fail('datetime', 'wire datetime domain value is outside the canonical RFC 3339 year range');
    }
    return Ok(formatted);
  }

  parseDuration(input: string): Result<Temporal.Duration, WireDateError> {
    return this.attempt('duration', `wire duration "${input}" is not a valid ISO 8601 duration`, () =>
      Temporal.Duration.from(input),
    ).andThen(duration =>
      duration.toString() === input
        ? Ok(duration)
        : this.fail(
            'duration',
            `wire duration must be the canonical Temporal spelling "${duration.toString()}", received "${input}"`,
          ),
    );
  }

  formatDuration(duration: Temporal.Duration): string {
    return duration.toString();
  }

  // Polyfill 0.5.1 has no Temporal.TimeZone: a ZonedDateTime validates and canonicalizes the id.
  parseTimeZone(input: string): Result<WireTimeZone, WireDateError> {
    return this.attempt(
      'timezone',
      `wire timezone "${input}" is not a known IANA time zone`,
      () => new Temporal.ZonedDateTime(0n, input).timeZoneId,
    ).andThen(canonical => {
      if (OFFSET_ZONE_PATTERN.test(canonical)) {
        return this.fail<WireTimeZone>(
          'timezone',
          `wire timezone must be a named IANA identifier, not a fixed offset, received "${input}"`,
        );
      }
      if (canonical !== input) {
        return this.fail<WireTimeZone>(
          'timezone',
          `wire timezone must be the canonical IANA id "${canonical}", received "${input}"`,
        );
      }
      return Ok(canonical as WireTimeZone);
    });
  }

  formatTimeZone(zone: WireTimeZone): Result<string, WireDateError> {
    return this.parseTimeZone(zone).map((id): string => id);
  }

  private attempt<T>(form: WireForm, message: string, parse: () => T): Result<T, WireDateError> {
    try {
      return Ok(parse());
    } catch (cause) {
      return this.fail(form, message, cause);
    }
  }

  private fail<T>(form: WireForm, message: string, cause?: unknown): Result<T, WireDateError> {
    return Err(new WireDateError(form, message, cause === undefined ? undefined : { cause }));
  }
}

export type { WireTimeZone };
export { WireDateCodec, WireDateError };
