import type { Result } from '@atomicloud/diene.result';
import { PortError } from './error.js';
import { type Checked, PortPolicy } from './validation.js';

type TelemetryPort = 'logging' | 'metrics';
type TelemetryAttributeValue = boolean | number | string;
type TelemetryAttributes = Readonly<Record<string, TelemetryAttributeValue>>;

class TelemetryPolicy extends PortPolicy {
  // biome-ignore lint/complexity/noUselessConstructor: Bun counts an implicit constructor as an uncovered function
  constructor() {
    super();
  }

  checkAttributes<P extends TelemetryPort>(
    attributes: TelemetryAttributes | undefined,
    port: P,
    operation: string,
  ): Checked<TelemetryAttributes | undefined, PortError<P>> {
    if (attributes === undefined) {
      return this.accept(undefined);
    }
    if (
      typeof attributes !== 'object' ||
      attributes === null ||
      Array.isArray(attributes) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(attributes))
    ) {
      return this.reject(
        new PortError(port, 'invalid-input', operation, 'Telemetry attributes must be a primitive record'),
      );
    }
    const entries = Object.entries(attributes);
    if (entries.some(([key]) => key.trim() === '' || key.includes('\0'))) {
      return this.reject(
        new PortError(port, 'invalid-input', operation, 'Telemetry attribute names must be non-blank and NUL-free'),
      );
    }
    if (
      entries.some(([, value]) => {
        const valueType = typeof value;
        return (
          (valueType !== 'string' && valueType !== 'number' && valueType !== 'boolean') ||
          (valueType === 'number' && !Number.isFinite(value))
        );
      })
    ) {
      return this.reject(
        new PortError(port, 'invalid-input', operation, 'Telemetry attribute values must be finite primitives'),
      );
    }
    return this.accept(
      Object.freeze(
        Object.fromEntries(entries.sort(([left], [right]) => (left === right ? 0 : left < right ? -1 : 1))),
      ),
    );
  }

  validateAttributes<P extends TelemetryPort>(
    attributes: TelemetryAttributes | undefined,
    port: P,
    operation: string,
  ): Result<TelemetryAttributes | undefined, PortError<P>> {
    return this.toResult(this.checkAttributes(attributes, port, operation));
  }
}

export type { TelemetryAttributes, TelemetryAttributeValue };
export { TelemetryPolicy };
