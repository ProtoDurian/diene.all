import type { ReleaserConfig } from '../../lib/config/model';
import { detectSchemaVersion, parseCanonicalV2 } from '../../lib/config/schema';
import { translateV1 } from '../../lib/config/translator';
import { DEFAULT_CONFIG_PATH, LEGACY_CONFIG_PATH } from '../../lib/config/paths';
import { ConfigError } from '../../lib/errors';
import type { IConfigRepository, IFileSystem, LoadedConfig } from '../../lib/release/ports';

export class YamlConfigRepository implements IConfigRepository {
  constructor(private readonly files: IFileSystem) {}

  async load(path: string): Promise<LoadedConfig> {
    // The legacy name is never read, only named, and only when the default was requested.
    if (
      path === DEFAULT_CONFIG_PATH &&
      !(await this.files.exists(path)) &&
      (await this.files.exists(LEGACY_CONFIG_PATH))
    ) {
      throw new ConfigError(
        `${path} not found, but ${LEGACY_CONFIG_PATH} exists. This tool formerly read ` +
          `${LEGACY_CONFIG_PATH}; rename it to ${path} (or pass -c ${LEGACY_CONFIG_PATH} to keep the old name).`,
      );
    }
    let raw: unknown;
    try {
      raw = Bun.YAML.parse(await this.files.readText(path));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new ConfigError(`failed to read YAML configuration "${path}": ${message}`);
    }
    const sourceVersion = detectSchemaVersion(raw);
    if (sourceVersion === 2) {
      return {
        config: parseCanonicalV2(raw),
        sourceVersion,
        warnings: [],
        legacyGitlintPath: '.gitlint',
      };
    }
    const translated = translateV1(raw);
    return {
      config: translated.config,
      sourceVersion,
      warnings: translated.warnings,
      legacyGitlintPath: translated.gitlintPath,
    };
  }

  async writeCanonical(path: string, config: ReleaserConfig): Promise<void> {
    const yaml = Bun.YAML.stringify(config, null, 2);
    await this.files.writeAtomic(path, `${yaml.trimEnd()}\n`);
  }
}
