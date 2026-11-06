class ConfigLoaderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigLoaderError';
  }
}

export { ConfigLoaderError };
