import type { ProbeRepo } from '@cyanprint/contracts';
import { capturedEnvCommand, restoreProbeState } from './helpers.ts';

// Cold Go module and build caches run past the parent helpers' 240 s cap.
const GO_TIMEOUT_MS = 600000;

export async function expectGreen(repo: any, command: string, label: string, timeoutMs = GO_TIMEOUT_MS): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs });
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
}

export async function expectRedWithDiagnostic(
  repo: any,
  command: string,
  label: string,
  expected: RegExp,
  timeoutMs = GO_TIMEOUT_MS,
): Promise<void> {
  const result = await repo.exec(capturedEnvCommand(command, label), { timeoutMs });
  if (result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
  const diagnostic = `${result.stdout}\n${result.stderr}`;
  if (!expected.test(diagnostic)) {
    throw new Error(`${label} failed for the wrong reason; expected ${expected}: ${diagnostic}`);
  }
}

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

async function first(repo: ProbeRepo, glob: string): Promise<string> {
  const paths = (await repo.glob(glob)).filter(path => !path.endsWith('_test.go')).sort();
  if (paths.length === 0) {
    throw new Error(`no structural Go target matched ${glob}`);
  }
  return paths[0];
}

export interface FlippedAssertion {
  path: string;
  // The gotestsum `=== FAIL: <package> <Test>` line the flipped assertion must produce.
  failure: RegExp;
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Flip the first `a != b` comparison (not an error check) in an `if` guard that sits directly in a top-level
// test body and guards a t.Fatal/t.Error call, so exactly that test fails by name. The guard may be an `||` chain:
// on a passing test every operand is false, so flipping one comparison fires it.
function flipGuard(line: string): string | undefined {
  const condition = line.match(/^\tif (.+) \{$/)?.[1];
  if (!condition || /&&|;|:=/.test(condition)) {
    return undefined;
  }
  const operands = condition.split(' || ');
  const index = operands.findIndex(operand => {
    const sides = operand.match(/^([^=!&|]+) != ([^=!&|]+)$/);
    return sides !== null && sides[1] !== 'nil' && sides[2] !== 'nil';
  });
  if (index < 0) {
    return undefined;
  }
  operands[index] = operands[index].replace(' != ', ' == ');
  return `\tif ${operands.join(' || ')} {`;
}

export async function flipComparisonAssertion(repo: ProbeRepo, glob: string): Promise<FlippedAssertion> {
  for (const path of (await repo.glob(glob)).sort()) {
    const lines = (await repo.read(path)).split('\n');
    let test = '';
    for (let index = 0; index < lines.length - 1; index++) {
      if (lines[index].startsWith('func ')) {
        test = lines[index].match(/^func (Test[A-Za-z0-9_]*)\(t \*testing\.T\) \{$/)?.[1] ?? '';
        continue;
      }
      const flipped = test ? flipGuard(lines[index]) : undefined;
      if (flipped && /^\t\tt\.(Fatal|Fatalf|Error|Errorf)\(/.test(lines[index + 1])) {
        lines[index] = flipped;
        await repo.write(path, lines.join('\n'));
        return { path, failure: new RegExp(`FAIL: ${escapeRegExp(directory(path))} ${test} `) };
      }
    }
  }
  throw new Error(`no structural Go assertion target found in ${glob}`);
}

export async function flipGoAssertion(repo: ProbeRepo): Promise<FlippedAssertion> {
  return flipComparisonAssertion(repo, 'tests/unit/**/*_test.go');
}

export async function plantWhiteBoxTest(repo: ProbeRepo): Promise<string> {
  const paths = (await repo.glob('tests/**/*_test.go')).sort();
  if (paths.length === 0) {
    throw new Error('no Go test package found');
  }
  const source = await repo.read(paths[0]);
  const external = packageName(source);
  if (!external.endsWith('_test')) {
    throw new Error('healthy test package is not external');
  }
  const target = `${directory(paths[0])}/probe_white_box_test.go`;
  await repo.write(
    target,
    `package ${external.slice(0, -5)}\n\nimport "testing"\n\nfunc TestProbeWhiteBox(t *testing.T) { t.Helper() }\n`,
  );
  return target;
}

export async function breakAdapter(repo: ProbeRepo): Promise<string> {
  const paths = (await repo.glob('adapters/**/*.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    const target = '.Set(ctx, key, value, 0)';
    if (source.includes(target)) {
      await repo.write(path, source.replace(target, '.Set(ctx, key+"-probe", value, 0)'));
      return path;
    }
  }
  throw new Error('no structural adapter method target found');
}

export async function plantGoFile(
  repo: ProbeRepo,
  glob: string,
  filename: string,
  declaration: string,
): Promise<string> {
  const path = await first(repo, glob);
  const packageDeclaration = packageName(await repo.read(path));
  const target = `${directory(path)}/${filename}`;
  await repo.write(target, `package ${packageDeclaration}\n\n${declaration}\n`);
  return target;
}

export async function plantProductionOnlySymbol(repo: ProbeRepo): Promise<string[]> {
  const tests = (await repo.glob('tests/unit/**/*_test.go')).sort();
  if (tests.length === 0) {
    throw new Error('no unit test package found');
  }
  const module = (await repo.read('go.mod')).match(/^module\s+(\S+)/m)?.[1];
  if (!module) {
    throw new Error('Go module path is missing');
  }
  const testPackage = packageName(await repo.read(tests[0]));
  const sourcePath = await plantGoFile(
    repo,
    'lib/**/*.go',
    'probe_production_only.go',
    'func ProbeProductionOnly() int { return 1 }',
  );
  const planted = [sourcePath];
  try {
    const sourceDirectory = directory(sourcePath);
    const importedPackage = packageName(await repo.read(sourcePath));
    const testPath = `${directory(tests[0])}/probe_production_only_test.go`;
    await repo.write(
      testPath,
      `package ${testPackage}\n\nimport (\n\t"testing"\n\t"${module}/${sourceDirectory}"\n)\n\nfunc TestProbeProductionOnly(t *testing.T) {\n\tt.Helper()\n\tif ${importedPackage}.ProbeProductionOnly() != 1 { t.Fatal("probe") }\n}\n`,
    );
    planted.push(testPath);
    return planted;
  } catch (error) {
    await restoreProbeState(repo, planted);
    throw error;
  }
}

export async function unformatGo(repo: ProbeRepo): Promise<string> {
  const path = await first(repo, 'lib/**/*.go');
  const source = await repo.read(path);
  const signature = source.match(/^func ([A-Z][A-Za-z0-9_]*)\(([^)]*)\)([^\n{]*) \{$/m);
  if (!signature) {
    throw new Error('no exported Go function signature found');
  }
  const unformatted = `func ${signature[1]}( ${signature[2]} )${signature[3]}{`;
  await repo.write(path, source.replace(signature[0], unformatted));
  return path;
}
