import type { ErrorPortalConfig } from './types.js';

const SEGMENT_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const PROBLEM_ID_PATTERN = /^[a-z][a-z0-9_]*$/;
const VERSION_PATTERN = /^v[0-9]+$/;
const HOST_FORBIDDEN_PATTERN = /[/\\\s@?#]/;

export class ProblemTypeUriBuilder {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor() {}

  buildProblemTypeUri(config: ErrorPortalConfig, version: string, id: string): string {
    const { scheme, host, landscape, platform, service, module } = config;
    if (host === '' || HOST_FORBIDDEN_PATTERN.test(host)) {
      throw new RangeError('ErrorPortal host must be a non-empty host or host:port without URL components');
    }
    this.validateSegment('landscape', landscape, SEGMENT_PATTERN);
    this.validateSegment('platform', platform, SEGMENT_PATTERN);
    this.validateSegment('service', service, SEGMENT_PATTERN);
    this.validateSegment('module', module, SEGMENT_PATTERN);
    this.validateSegment('version', version, VERSION_PATTERN);
    this.validateSegment('id', id, PROBLEM_ID_PATTERN);

    const uri = `${scheme}://${host}/docs/${landscape}/${platform}/${service}/${module}/${version}/${id}`;
    this.assertCanonicalHost(uri, host);
    return uri;
  }

  private validateSegment(name: string, value: string, pattern: RegExp): void {
    if (!pattern.test(value)) {
      throw new RangeError(`${name} must match ${pattern}; received ${JSON.stringify(value)}`);
    }
  }

  private assertCanonicalHost(uri: string, host: string): void {
    let parsed: URL;
    try {
      parsed = new URL(uri);
    } catch (error: unknown) {
      throw new RangeError(`Invalid ErrorPortal host ${JSON.stringify(host)}`, { cause: error });
    }
    if (parsed.host !== host) {
      throw new RangeError('ErrorPortal host is not a canonical host or host:port');
    }
  }
}
