import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { GenericContainer, type StartedTestContainer, Wait } from 'testcontainers';
import { BinaryCliDriver, type CliDriver, type CliResult, InProcessCliDriver } from './driver';

// SIT journeys against a real Redis; SIT_DRIVER picks the compiled binary (default, no coverage) or in-process (coverage).
const useInProcess = process.env.SIT_DRIVER === 'inprocess';

let container: StartedTestContainer | undefined;
let driver: CliDriver;

async function cli(args: string[], env: Record<string, string> = {}): Promise<CliResult> {
  return driver.run(args, env);
}

beforeAll(async () => {
  container = await new GenericContainer('redis:7.4.5-alpine')
    .withExposedPorts(6379)
    .withWaitStrategy(Wait.forLogMessage(/Ready to accept connections/))
    .start();
  const host = container.getHost();
  const port = container.getMappedPort(6379);
  if (useInProcess) {
    driver = new InProcessCliDriver(host, port);
  } else {
    const os = process.platform === 'darwin' ? 'darwin' : 'linux';
    const arch = process.arch === 'arm64' ? 'arm64' : 'x64-baseline';
    const bin = process.env.CLI_BIN ?? `dist/bin/bun-cli-${os}-${arch}`;
    driver = new BinaryCliDriver(bin, { REDIS_HOST: host, REDIS_PORT: String(port) });
  }
}, 120_000);

afterAll(async () => {
  await container?.stop();
}, 120_000);

describe(`bun-cli (SIT, ${useInProcess ? 'in-process' : 'compiled binary'})`, () => {
  it('prints a semver with --version', async () => {
    // Act
    const actual = await cli(['--version']);

    // Assert
    actual.code.should.equal(0);
    actual.out.trim().should.match(/^\d+\.\d+\.\d+/);
  });

  it('lists every command in --help', async () => {
    // Act
    const actual = await cli(['--help']);

    // Assert
    actual.code.should.equal(0);
    for (const command of ['set', 'get', 'seed', 'doctor']) actual.out.should.containEql(command);
  });

  it('round-trips set then get', async () => {
    // Arrange
    const set = await cli(['set', 'sit', 'greeting', 'hello']);
    set.code.should.equal(0);

    // Act
    const get = await cli(['get', 'sit', 'greeting']);

    // Assert
    get.code.should.equal(0);
    get.out.should.containEql('hello');
  });

  it('accepts set --ttl and the value is readable', async () => {
    // Arrange
    const set = await cli(['set', 'sit', 'ephemeral', 'soon-gone', '--ttl', '60']);
    set.code.should.equal(0);

    // Act
    const get = await cli(['get', 'sit', 'ephemeral']);

    // Assert
    get.out.should.containEql('soon-gone');
  });

  it('reports not-found with a non-zero exit', async () => {
    // Act
    const actual = await cli(['get', 'sit', 'missing-key']);

    // Assert
    actual.code.should.not.equal(0);
    actual.out.should.containEql('not found');
  });

  it('rejects an invalid --ttl with a non-zero exit', async () => {
    // Act
    const actual = await cli(['set', 'sit', 'k', 'v', '--ttl', 'abc']);

    // Assert
    actual.code.should.not.equal(0);
    actual.err.should.containEql('invalid input');
  });

  it('seeds N entries readable afterwards', async () => {
    // Arrange
    const seed = await cli(['seed', 'sit-seed', '5']);
    seed.code.should.equal(0);
    seed.out.should.containEql('seeded 5 entries');

    // Act
    const get = await cli(['get', 'sit-seed', 'sample-3']);

    // Assert
    get.out.should.containEql('value-3');
  });

  it('rejects a non-numeric seed count', async () => {
    // Act
    const actual = await cli(['seed', 'sit-seed', 'abc']);

    // Assert
    actual.code.should.not.equal(0);
    actual.err.should.containEql('invalid input');
  });

  it('doctor reports platform and a reachable backend', async () => {
    // Act
    const actual = await cli(['doctor']);

    // Assert
    actual.code.should.equal(0);
    actual.out.should.containEql('platform:');
    (actual.out + actual.err).should.containEql('reachable');
  });

  it('doctor exits non-zero when the backend is unreachable', async () => {
    // Act
    const actual = await cli(['doctor'], { REDIS_HOST: '127.0.0.1', REDIS_PORT: '1' });

    // Assert
    actual.code.should.not.equal(0);
  });

  it('rejects a blank Redis host before touching the backend', async () => {
    // Act
    const actual = await cli(['doctor'], { REDIS_HOST: '   ' });

    // Assert
    actual.code.should.not.equal(0);
    actual.err.should.containEql('REDIS_HOST');
  });

  it('fails an unknown command with help output', async () => {
    // Act
    const actual = await cli(['bogus']);

    // Assert
    actual.code.should.not.equal(0);
    actual.err.toLowerCase().should.containEql('unknown command');
  });
});
