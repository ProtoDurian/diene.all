import { afterAll, beforeAll, describe, it } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import 'should';
import { z } from 'zod';
import { YamlConfigSource, YamlConfigSourceError } from '../../src/adapters/yaml-source.js';
import { ConfigLoader } from '../../src/lib/loader.js';
import { ConfigRegistry } from '../../src/lib/registry.js';

const PREFIX = 'ATOMI_';
const registry = ConfigRegistry.create().register(
  'server',
  z.object({ port: z.number(), host: z.string(), tags: z.array(z.string()) }),
);

let dir: string;

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), 'diene-config-int-'));
  await writeFile(
    join(dir, 'config.yaml'),
    '# yaml-language-server: $schema=./schema.json\nserver:\n  port: 80\n  host: base-host\n  tags:\n    - a\n    - b\n',
  );
  await writeFile(join(dir, 'prod.config.yaml'), 'server:\n  host: prod-host\n');
  await writeFile(join(dir, 'custom.yaml'), 'server:\n  port: 1\n  host: custom-host\n  tags: []\n');
  await writeFile(join(dir, 'empty.config.yaml'), '');
  await writeFile(join(dir, 'broken.config.yaml'), '- just\n- a\n- list\n');
  await writeFile(join(dir, 'typo.config.yaml'), 'server: [unclosed\n');
});

afterAll(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe('YamlConfigSource through the full loader', () => {
  it('should merge base, overlay and runtime env with an indexed-list override', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: { ATOMI_SERVER__PORT: '8080', ATOMI_SERVER__TAGS__1: 'z' } });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX, landscape: 'prod' }).load();

    // Assert
    config.get('server').should.deepEqual({ port: 8080, host: 'prod-host', tags: ['a', 'z'] });
  });

  it('should treat a missing overlay file as an empty overlay', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: {} });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX, landscape: 'staging' }).load();

    // Assert
    config.get('server').host.should.equal('base-host');
  });

  it('should read runtime values from the real process.env by default', async () => {
    // Arrange
    process.env.ATOMI_SERVER__PORT = '9090';
    const source = new YamlConfigSource({ dir });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX }).load().finally(() => {
      delete process.env.ATOMI_SERVER__PORT;
    });

    // Assert
    config.get('server').port.should.equal(9090);
  });

  it('should apply the build-time env map before runtime env', async () => {
    // Arrange
    const source = new YamlConfigSource({
      dir,
      buildTimeEnv: { ATOMI_SERVER__HOST: 'build-host', ATOMI_SERVER__PORT: '1' },
      env: { ATOMI_SERVER__PORT: '2' },
    });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX }).load();

    // Assert
    config.get('server').should.deepEqual({ port: 2, host: 'build-host', tags: ['a', 'b'] });
  });

  it('should honour a custom base file and overlay naming', async () => {
    // Arrange
    const source = new YamlConfigSource({
      dir,
      baseFile: 'custom.yaml',
      overlayFile: name => `${name}.config.yaml`,
      env: {},
    });

    // Act
    const config = await new ConfigLoader(source, registry, { prefix: PREFIX, landscape: 'prod' }).load();

    // Assert
    config.get('server').should.deepEqual({ port: 1, host: 'prod-host', tags: [] });
  });
});

describe('YamlConfigSource tiers', () => {
  it.each([
    { label: 'an empty overlay file', landscape: 'empty' },
    { label: 'an absent overlay file', landscape: 'absent' },
  ])('should read $label as an empty object', async ({ landscape }) => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: {} });

    // Act
    const overlay = await source.overlay(landscape);

    // Assert
    overlay.should.deepEqual({});
  });

  it('should reject a YAML file that is not a mapping', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: {} });

    // Act
    const act = source.overlay('broken');

    // Assert
    await act.should.be.rejectedWith(YamlConfigSourceError);
  });

  it('should reject when the required base file is missing', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, baseFile: 'does-not-exist.yaml', env: {} });

    // Act
    const act = source.base();

    // Assert
    await act.should.be.rejectedWith({ code: 'ENOENT' });
  });

  it('should name the file and keep the cause when the YAML does not parse', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, env: {} });

    // Act
    const error: object = await source.overlay('typo').then(
      () => ({}),
      (reason: Error) => reason,
    );

    // Assert
    error.should.be.instanceof(YamlConfigSourceError);
    (error as Error).message.should.startWith(`${join(dir, 'typo.config.yaml')}: `);
    ((error as Error).cause as Error).name.should.equal('YAMLParseError');
  });

  it('should rethrow an overlay read error other than a missing file', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir, overlayFile: () => '.', env: {} });

    // Act
    const act = source.overlay('prod');

    // Assert
    await act.should.be.rejectedWith({ code: 'EISDIR' });
  });

  it('should default the build-time env to empty', async () => {
    // Arrange
    const source = new YamlConfigSource({ dir });

    // Act
    const buildTime = await source.buildTimeEnv();

    // Assert
    buildTime.should.deepEqual({});
  });
});
