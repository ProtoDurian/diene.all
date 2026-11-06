export class ReleaserError extends Error {
  constructor(message: string) {
    super(message);
    this.name = new.target.name;
  }
}

export class ConfigError extends ReleaserError {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor(message: string) {
    super(message);
  }
}

export class UnsupportedModuleError extends ConfigError {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor(message: string) {
    super(message);
  }
}

export class ReleaseError extends ReleaserError {
  constructor(
    message: string,
    readonly phase: string,
  ) {
    super(message);
  }
}

export class GitError extends ReleaserError {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor(message: string) {
    super(message);
  }
}

export class HookError extends ReleaserError {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor(message: string) {
    super(message);
  }
}

export class GitHubError extends ReleaserError {
  // biome-ignore lint/complexity/noUselessConstructor: Bun coverage counts an implicit constructor as an uncovered function
  constructor(message: string) {
    super(message);
  }
}
