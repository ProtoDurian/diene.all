module.exports = {
  compilationOptions: {
    preferredConfigPath: './tsconfig.json',
  },
  entries: [
    { filePath: './src/index.ts', outFile: './dist/index.d.ts', noCheck: true },
    { filePath: './src/build-time.ts', outFile: './dist/build-time.d.ts', noCheck: true },
  ],
};
