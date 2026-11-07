import { describe, it } from 'bun:test';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import 'should';
import { NodeTlsFileReader, OtlpAgentOptionsFactory, OtlpTlsFileError } from '../../src/adapters/signals/tls';

function certificateDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), 'otel-tls-'));
  writeFileSync(join(directory, 'ca.pem'), 'ca');
  writeFileSync(join(directory, 'client.pem'), 'cert');
  writeFileSync(join(directory, 'client.key'), 'key');
  return directory;
}

describe('OtlpAgentOptionsFactory', () => {
  it('should keep the connection alive and read nothing when no file is named', () => {
    // Arrange
    const factory = new OtlpAgentOptionsFactory();

    // Act
    const actual = factory.create({});

    // Assert
    actual.should.eql({ keepAlive: true });
  });

  it('should read the named files into the agent options', () => {
    // Arrange
    const directory = certificateDirectory();
    const factory = new OtlpAgentOptionsFactory(new NodeTlsFileReader());

    // Act
    const actual = factory.create({
      ca: { path: join(directory, 'ca.pem'), variable: 'OTEL_EXPORTER_OTLP_CERTIFICATE' },
      cert: { path: join(directory, 'client.pem'), variable: 'OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE' },
      key: { path: join(directory, 'client.key'), variable: 'OTEL_EXPORTER_OTLP_CLIENT_KEY' },
    });

    // Assert
    actual.should.eql({ keepAlive: true, ca: Buffer.from('ca'), cert: Buffer.from('cert'), key: Buffer.from('key') });
  });

  it('should fail naming the variable when a named file cannot be read', () => {
    // Arrange
    const factory = new OtlpAgentOptionsFactory();
    const missing = join(certificateDirectory(), 'missing.pem');

    // Act
    const actual = (() => {
      try {
        factory.create({ key: { path: missing, variable: 'OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY' } });
        return undefined;
      } catch (error) {
        return error;
      }
    })();

    // Assert
    (actual instanceof OtlpTlsFileError).should.be.true();
    (actual as OtlpTlsFileError).should.match({
      name: 'OtlpTlsFileError',
      variable: 'OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY',
      path: missing,
    });
    (actual as Error).message.should.startWith(
      `OTEL_EXPORTER_OTLP_TRACES_CLIENT_KEY names an unreadable file ${missing}: `,
    );
  });

  it('should describe a non-Error read failure', () => {
    // Arrange
    const factory = new OtlpAgentOptionsFactory({
      read: () => {
        throw 'denied';
      },
    });

    // Act
    const actual = (() => {
      try {
        factory.create({ ca: { path: 'ca.pem', variable: 'OTEL_EXPORTER_OTLP_CERTIFICATE' } });
        return undefined;
      } catch (error) {
        return error as OtlpTlsFileError;
      }
    })();

    // Assert
    (actual?.message ?? '').should.eql('OTEL_EXPORTER_OTLP_CERTIFICATE names an unreadable file ca.pem: denied');
    (actual?.cause ?? '').should.eql('denied');
  });
});

describe('OtlpTlsFileError identity', () => {
  class NarrowTlsFileError extends OtlpTlsFileError {}

  it.each([
    ['a TLS file error', new OtlpTlsFileError('V', 'p', 'x'), OtlpTlsFileError, true],
    [
      'a branded look-alike from the other build',
      { [Symbol.for('AtomiCloud.Diene.Otel.OtlpTlsFileError')]: true },
      OtlpTlsFileError,
      true,
    ],
    ['a plain Error', new Error('m'), OtlpTlsFileError, false],
    ['null', null, OtlpTlsFileError, false],
    ['a base error against a subclass', new OtlpTlsFileError('V', 'p', 'x'), NarrowTlsFileError, false],
    ['a subclass error against the subclass', new NarrowTlsFileError('V', 'p', 'x'), NarrowTlsFileError, true],
  ])('should judge %s', (_label, value, type, expected) => {
    // Arrange
    const candidate: unknown = value;

    // Act
    const actual = candidate instanceof (type as typeof OtlpTlsFileError);

    // Assert
    actual.should.eql(expected);
  });
});
