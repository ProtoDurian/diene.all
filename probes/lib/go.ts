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

export async function flipGoAssertion(repo: ProbeRepo): Promise<string> {
  const paths = (await repo.glob('tests/unit/**/*_test.go')).sort();
  for (const path of paths) {
    const source = await repo.read(path);
    if (source.includes('; got != ')) {
      await repo.write(path, source.replace('; got != ', '; got == '));
      return path;
    }
  }
  throw new Error('no structural Go assertion target found');
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

const imagePolicies = {
  distroless: {
    rule: 'final runtime image must use the distroless nonroot base',
    subject: 'final stage base image',
    expected: 'FROM gcr.io/distroless/static-debian12:nonroot AS runtime',
  },
  nonroot: {
    rule: 'final runtime image must run as 65532:65532',
    subject: 'final stage effective user',
    expected: 'USER 65532:65532',
  },
};

type ImagePolicy = keyof typeof imagePolicies;

function imagePolicyViolation(dockerfile: string, policy: ImagePolicy): string | undefined {
  let from = '';
  let user = '';
  for (const line of dockerfile.split('\n')) {
    const words = line
      .trim()
      .split(/\s+/)
      .filter(word => !word.startsWith('--'));
    const keyword = words[0]?.toUpperCase();
    if (keyword === 'FROM') {
      from =
        words.length === 4 && words[2].toUpperCase() === 'AS' ? `${words[1]} AS ${words[3]}` : words.slice(1).join(' ');
      user = '';
    } else if (keyword === 'USER') {
      user = words.slice(1).join(' ');
    }
  }
  const { rule, subject, expected } = imagePolicies[policy];
  const observed = policy === 'distroless' ? `FROM ${from}` : user ? `USER ${user}` : '<none declared>';
  return observed === expected ? undefined : `${rule}: ${subject} is '${observed}', expected '${expected}'`;
}

export async function expectImagePolicyGreen(repo: ProbeRepo, policy: ImagePolicy): Promise<void> {
  const violation = imagePolicyViolation(await repo.read('infra/Dockerfile'), policy);
  if (violation) {
    throw new Error(`${policy} image policy failed on the healthy repo: ${violation}`);
  }
}

export async function expectImagePolicyRed(repo: ProbeRepo, policy: ImagePolicy): Promise<void> {
  const violation = imagePolicyViolation(await repo.read('infra/Dockerfile'), policy);
  if (!violation?.startsWith(imagePolicies[policy].rule)) {
    throw new Error(`${policy} image policy stayed green after sabotage`);
  }
}
