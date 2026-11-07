import type { ProbeRepo } from '@cyanprint/contracts';
import { type FlippedAssertion, flipComparisonAssertion, plantGoFile } from './go.ts';

async function sources(repo: ProbeRepo, glob: string): Promise<string[]> {
  return (await repo.glob(glob)).filter(path => !path.endsWith('_test.go')).sort();
}

export async function plantVetMisuse(repo: ProbeRepo): Promise<string> {
  return plantGoFile(
    repo,
    'lib/**/*.go',
    'probe_vet.go',
    'import "fmt"\n\n// ProbeVet misuses a format verb.\nfunc ProbeVet() string { return fmt.Sprintf("%d", "not-an-integer") }',
  );
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

export async function flipMetaAssertion(repo: ProbeRepo): Promise<FlippedAssertion> {
  return flipComparisonAssertion(repo, 'tests/meta/**/*_test.go');
}

export async function plantUncoveredTestHelper(repo: ProbeRepo): Promise<string> {
  return plantGoFile(
    repo,
    'testhelper/**/*.go',
    'probe_uncovered.go',
    '// ProbeUncovered is never exercised by a meta test.\nfunc ProbeUncovered() bool { return true }',
  );
}
