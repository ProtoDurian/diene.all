// dts-bundle-generator config: emit flat, self-contained declarations for the
// root and /build-time entry points from a SINGLE TypeScript program. Sharing the
// program pays zod's heavy type-loading cost once instead of per entry.
module.exports = {
  compilationOptions: {
    preferredConfigPath: './tsconfig.json',
  },
  entries: [
    { filePath: './src/index.ts', outFile: './dist/index.d.ts', noCheck: true },
    { filePath: './src/build-time.ts', outFile: './dist/build-time.d.ts', noCheck: true },
  ],
};
