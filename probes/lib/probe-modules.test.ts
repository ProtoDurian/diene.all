import { describe, expect, test } from 'bun:test';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

// Nothing else imports the probe modules; a module-scope throw voids a whole engine run.
const probesDir = fileURLToPath(new URL('../', import.meta.url));
const probeFiles = readdirSync(probesDir)
  .filter(name => name.endsWith('.ts'))
  .sort();

describe('every probe module loads', () => {
  test('the probe set is non-empty, so an empty glob cannot pass this vacuously', () => {
    expect(probeFiles.length).toBeGreaterThan(20);
  });

  for (const file of probeFiles) {
    test(`${file} imports without throwing`, async () => {
      const loaded = await import(join(probesDir, file));
      expect(loaded.default).toBeDefined();
      expect(Array.isArray(loaded.default.probes)).toBe(true);
    });
  }
});
