import type { ITagReader } from './ports';

type GuardCode = 'tag-collision' | 'tag-not-visible' | 'invalid-version' | 'shallow-clone' | 'not-a-git-repo';

export interface GuardRefusal {
  readonly code: GuardCode;
  readonly message: string;
}

// Prerelease is captured, not found via indexOf('-'): build metadata may contain dashes.
const FULL_VERSION =
  /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?$/;

interface SemVer {
  readonly raw: string;
  readonly major: number;
  readonly minor: number;
  readonly patch: number;
  readonly prerelease: string;
}

// Floating major tags (v3, v3.1) must not parse: semantic-release-major-tag moves them.
function parseVersion(tag: string): SemVer | null {
  const match = FULL_VERSION.exec(tag);
  if (match === null) return null;
  return {
    raw: tag,
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    prerelease: match[4] ?? '',
  };
}

function compareVersion(left: SemVer, right: SemVer): number {
  if (left.major !== right.major) return left.major - right.major;
  if (left.minor !== right.minor) return left.minor - right.minor;
  if (left.patch !== right.patch) return left.patch - right.patch;
  if (left.prerelease === right.prerelease) return 0;
  if (left.prerelease === '') return 1;
  if (right.prerelease === '') return -1;
  return left.prerelease < right.prerelease ? -1 : 1;
}

export function renderRefusal(refusal: GuardRefusal): string {
  return `${refusal.code}: ${refusal.message}`;
}

interface TagSnapshot {
  readonly refusal: GuardRefusal | null;
  readonly all: readonly string[];
  readonly visible: readonly string[];
}

export class TagGuard {
  constructor(private readonly tags: ITagReader) {}

  async checkVisibility(): Promise<GuardRefusal | null> {
    const snapshot = await this.snapshot();
    if (snapshot.refusal !== null) return snapshot.refusal;

    const versions = snapshot.all.map(parseVersion).filter((tag): tag is SemVer => tag !== null);
    const visible = new Set(snapshot.visible);
    const unreachable = versions.filter(tag => !visible.has(tag.raw));
    if (unreachable.length === 0) return null;

    const highest = unreachable.reduce((left, right) => (compareVersion(left, right) >= 0 ? left : right));
    return {
      code: 'tag-not-visible',
      message:
        `${unreachable.length} version tag(s) exist in this repository but are NOT reachable from HEAD ` +
        `(highest: ${highest.raw}; all: ${unreachable.map(tag => tag.raw).join(', ')}). ` +
        'The next version is computed from reachable tags only, so it can be computed onto one of these. ' +
        'Tagging happens after the release commit, so the commit and changelog would land and only then ' +
        "would tagging fail, leaving a committed release with no tag. Fetch the tags into this branch's " +
        'history, or delete them deliberately, before releasing.',
    };
  }

  async checkVersion(version: string, tag: string): Promise<GuardRefusal | null> {
    if (parseVersion(version) === null) {
      return {
        code: 'invalid-version',
        message:
          `\`${version}\` is not a full version (expected \`x.y.z\`, optionally \`v\`-prefixed); ` +
          'refusing rather than guessing what to check',
      };
    }

    const snapshot = await this.snapshot();
    if (snapshot.refusal !== null) return snapshot.refusal;

    const bare = version.startsWith('v') ? version.slice(1) : version;
    const candidates = [...new Set([bare, `v${bare}`, tag])];
    const taken = snapshot.all.filter(existing => candidates.includes(existing));
    if (taken.length === 0) return null;

    return {
      code: 'tag-collision',
      message:
        `tag(s) ${taken.join(', ')} already exist in this repository, so version ${bare} is already taken. ` +
        "Existence is the only test applied: the tag's author, date, annotation and reachability are not " +
        'consulted, because a tag minted by a human owner blocks a release exactly as hard as one minted ' +
        'by a machine.',
    };
  }

  // A shallow or unreadable repository refuses; it never passes.
  private async snapshot(): Promise<TagSnapshot> {
    const empty = { all: [], visible: [] } as const;
    try {
      if (await this.tags.isShallow()) {
        return {
          ...empty,
          refusal: {
            code: 'shallow-clone',
            message:
              'this is a shallow clone, so the tag set is incomplete and a collision cannot be ruled out. ' +
              'Refusing instead of reporting a clear result from an incomplete population. Fetch full ' +
              'history and tags (`git fetch --unshallow --tags`) before releasing.',
          },
        };
      }
      return { refusal: null, all: await this.tags.allTags(), visible: await this.tags.visibleTags() };
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      return { ...empty, refusal: { code: 'not-a-git-repo', message: `cannot inspect tags: ${detail}` } };
    }
  }
}
