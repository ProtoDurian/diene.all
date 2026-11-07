import type { z } from 'zod';

const VALIDATION_ERROR_BRAND = Symbol.for('AtomiCloud.Diene.Config.ConfigValidationError');

class ConfigValidationError extends Error {
  readonly issues: readonly string[];

  // The ESM and CJS builds each carry this class; the brand makes instanceof hold across them.
  static override [Symbol.hasInstance](value: unknown): boolean {
    // biome-ignore lint/complexity/noThisInStatic: this is the class instanceof was called on; the class-name fix breaks subclasses
    if (this !== ConfigValidationError) return Function.prototype[Symbol.hasInstance].call(this, value);
    return typeof value === 'object' && value !== null && VALIDATION_ERROR_BRAND in value;
  }

  constructor(issues: readonly string[]) {
    super(`configuration validation failed on the final merged layer: ${issues.join('; ')}`);
    this.name = 'ConfigValidationError';
    this.issues = issues;
    Object.defineProperty(this, VALIDATION_ERROR_BRAND, { value: true });
  }
}

class ConfigValidator {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  validate<T>(schema: z.ZodType<T>, value: unknown): T {
    const parsed = schema.safeParse(value);
    if (parsed.success) return parsed.data;
    throw new ConfigValidationError(
      parsed.error.issues.map(
        issue => `${issue.path.length > 0 ? issue.path.map(String).join('.') : '(root)'}: ${issue.message}`,
      ),
    );
  }
}

export { ConfigValidationError, ConfigValidator };
