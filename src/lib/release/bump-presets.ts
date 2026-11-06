import { ReleaserError } from '../errors';

export class BumpError extends ReleaserError {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor(message: string) {
    super(message);
  }
}

export type BumpTypeName = 'node-version' | 'dart-version' | 'dotnet-version' | 'plain-version';

interface BumpOutcome {
  readonly content: string;
  readonly from: string;
}

export interface BumpPreset {
  readonly type: BumpTypeName;
  readonly defaultFile: string | null;
  readonly field: string;
  apply(path: string, content: string, version: string): BumpOutcome;
}

const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9.+-]*$/;

export function normalizeVersion(version: string): string {
  return /^v\d/.test(version) ? version.slice(1) : version;
}

function assertUsableVersion(version: string): string {
  const normalized = normalizeVersion(version);
  if (!VERSION_PATTERN.test(normalized))
    throw new BumpError(
      `${JSON.stringify(version)} is not a usable version: expected only alphanumerics, dot, plus and hyphen, ` +
        'starting with an alphanumeric',
    );
  return normalized;
}

function soleMatch(matches: readonly RegExpMatchArray[], path: string, field: string): RegExpMatchArray {
  if (matches.length === 0)
    throw new BumpError(
      `${path} declares no ${field}; refusing to create one, because introducing a version field is a ` +
        'project-shape change rather than a bump',
    );
  if (matches.length > 1)
    throw new BumpError(
      `${path} declares ${field} ${matches.length} times; refusing to guess which one to bump — ` +
        'name the file explicitly or remove the duplicate',
    );
  return matches[0] as RegExpMatchArray;
}

function replaceCapture(content: string, match: RegExpMatchArray, capture: string, version: string): string {
  const start = (match.index ?? 0) + match[0].indexOf(capture);
  return content.slice(0, start) + version + content.slice(start + capture.length);
}

function buildPreset(
  type: BumpTypeName,
  defaultFile: string | null,
  field: string,
  pattern: RegExp,
  captureIndex: number,
): BumpPreset {
  return {
    type,
    defaultFile,
    field,
    apply(path, content, version) {
      const normalized = assertUsableVersion(version);
      const matches = [...content.matchAll(pattern)];
      const match = soleMatch(matches, path, field);
      const from = match[captureIndex] as string;
      return { content: replaceCapture(content, match, from, normalized), from };
    },
  };
}

// Two-space anchor so a nested "version" (dependencies, workspaces) never matches.
const NODE_VERSION = /^ {2}"version"\s*:\s*"([^"]*)"/gm;

const DART_VERSION = /^version\s*:\s*["']?([^\s"'#]+)["']?/gm;

const DOTNET_VERSION = /<Version>([^<]*)<\/Version>/g;

const PLAIN_VERSION = /^[ \t]*(\S+)[ \t]*$/gm;

const PRESETS: readonly BumpPreset[] = [
  buildPreset('node-version', 'package.json', 'a top-level "version"', NODE_VERSION, 1),
  buildPreset('dart-version', 'pubspec.yaml', 'a top-level version', DART_VERSION, 1),
  // No dotnet default: real trees keep the version in different files.
  buildPreset('dotnet-version', null, 'a <Version> property', DOTNET_VERSION, 1),
  buildPreset('plain-version', 'VERSION', 'a version line', PLAIN_VERSION, 1),
];

const BY_NAME = new Map(PRESETS.map(preset => [preset.type, preset]));

export function bumpPreset(type: BumpTypeName): BumpPreset {
  const preset = BY_NAME.get(type);
  if (preset === undefined) throw new BumpError(`unknown bump type ${JSON.stringify(type)}`);
  return preset;
}

export function bumpPresetNames(): readonly BumpTypeName[] {
  return PRESETS.map(preset => preset.type);
}

export function bumpPath(type: BumpTypeName, file: string | null): string {
  const preset = bumpPreset(type);
  const path = file ?? preset.defaultFile;
  if (path === null) throw new BumpError(`${type} has no default file, so the bump entry must name one explicitly`);
  return path;
}
