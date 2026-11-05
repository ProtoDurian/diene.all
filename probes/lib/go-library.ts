import type { ProbeRepo } from '@cyanprint/contracts';

function directory(path: string): string {
  return path.slice(0, path.lastIndexOf('/'));
}

function packageName(source: string): string {
  const name = source.match(/^package\s+([A-Za-z0-9_]+)/m)?.[1];
  if (!name) {
    throw new Error('could not infer Go package');
  }
  return name;
}

async function sources(repo: ProbeRepo, glob: string): Promise<string[]> {
  return (await repo.glob(glob)).filter(path => !path.endsWith('_test.go')).sort();
}

export async function plantVetMisuse(repo: ProbeRepo): Promise<string> {
  const [path] = await sources(repo, 'lib/**/*.go');
  if (!path) {
    throw new Error('no Go library source found');
  }
  const target = `${directory(path)}/probe_vet.go`;
  await repo.write(
    target,
    `package ${packageName(await repo.read(path))}\n\nimport "fmt"\n\n// ProbeVet misuses a format verb.\nfunc ProbeVet() string { return fmt.Sprintf("%d", "not-an-integer") }\n`,
  );
  return target;
}

export async function renameExportedFunction(repo: ProbeRepo): Promise<string> {
  for (const path of await sources(repo, '{lib,adapters,testhelper}/**/*.go')) {
    const source = await repo.read(path);
    const name = source.match(/^func ([A-Z][A-Za-z0-9_]*)\(/m)?.[1];
    if (name) {
      await repo.write(path, source.replace(`func ${name}(`, `func ${name}Probe(`));
      return name;
    }
  }
  throw new Error('no exported Go function found');
}

export async function stripExportDoc(repo: ProbeRepo): Promise<string> {
  for (const path of await sources(repo, '{lib,adapters,testhelper}/**/*.go')) {
    const source = await repo.read(path);
    const documented = source.match(/^\/\/ ([A-Z][A-Za-z0-9_]*) [^\n]*\n(?:func|type) \1\b/m);
    if (documented) {
      await repo.write(path, source.replace(`${documented[0].split('\n')[0]}\n`, ''));
      return documented[1];
    }
  }
  throw new Error('no documented export found');
}

export async function breakExampleOutput(repo: ProbeRepo): Promise<string> {
  for (const path of (await repo.glob('{lib,adapters,testhelper}/**/*_test.go')).sort()) {
    const source = await repo.read(path);
    if (/^func Example/m.test(source) && source.includes('// Output: ')) {
      await repo.write(path, source.replace(/\/\/ Output: [^\n]+/, '// Output: probe-wrong-output'));
      return path;
    }
  }
  throw new Error('no Go example with checked output found');
}

export async function flipMetaAssertion(repo: ProbeRepo): Promise<string> {
  for (const path of (await repo.glob('tests/meta/**/*_test.go')).sort()) {
    const source = await repo.read(path);
    if (source.includes('if got != created {')) {
      await repo.write(path, source.replace('if got != created {', 'if got == created {'));
      return path;
    }
  }
  throw new Error('no meta assertion target found');
}

export async function plantUncoveredTestHelper(repo: ProbeRepo): Promise<string> {
  const [path] = await sources(repo, 'testhelper/**/*.go');
  if (!path) {
    throw new Error('no testhelper source found');
  }
  const target = `${directory(path)}/probe_uncovered.go`;
  await repo.write(
    target,
    `package ${packageName(await repo.read(path))}\n\n// ProbeUncovered is never exercised by a meta test.\nfunc ProbeUncovered() bool { return true }\n`,
  );
  return target;
}
