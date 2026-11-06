import { describe, it } from 'bun:test';
import 'should';
import { ExporterSelector, OtelEnvironment } from '../../src/lib/environment';
import { defaultOtelBlock, type OtelBlock, type OtelExporter } from '../../src/lib/schema';

const bothOn: OtelExporter = {
  console: { enabled: true },
  otlp: { enabled: true, endpoint: 'http://c:4318', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' },
};
const allOn: OtelBlock = {
  logs: { enabled: true, exporter: bothOn },
  metrics: { ...defaultOtelBlock.metrics, exporter: bothOn },
  traces: { ...defaultOtelBlock.traces, enabled: false, exporter: bothOn },
};
const selector = new ExporterSelector();

describe('OtelEnvironment', () => {
  it.each([
    ['a populated value', { NAME: ' value ' }, 'value'],
    ['a whitespace value', { NAME: '   ' }, undefined],
    ['an absent value', {}, undefined],
  ])('should read %s', (_label, values, expected) => {
    // Arrange
    const environment = new OtelEnvironment(values);

    // Act
    const actual = environment.value('NAME');

    // Assert
    (actual ?? 'absent').should.eql(expected ?? 'absent');
    environment.has('NAME').should.eql(expected !== undefined);
  });

  it.each([
    ['lowercase true', { OTEL_SDK_DISABLED: 'true' }, true],
    ['padded upper case', { OTEL_SDK_DISABLED: '  TRUE ' }, true],
    ['false', { OTEL_SDK_DISABLED: 'false' }, false],
    ['unset', {}, false],
  ])('should report the SDK disabled flag when %s', (_label, values, expected) => {
    // Arrange
    const environment = new OtelEnvironment(values);

    // Act
    const actual = environment.sdkDisabled();

    // Assert
    actual.should.eql(expected);
  });
});

describe('ExporterSelector.select', () => {
  it.each([
    ['absent', {}, { console: true, otlp: true }],
    ['none', { OTEL_TRACES_EXPORTER: 'none' }, { console: false, otlp: false }],
    ['console alone', { OTEL_TRACES_EXPORTER: 'console' }, { console: true, otlp: false }],
    ['padded console and otlp', { OTEL_TRACES_EXPORTER: ' Console , OTLP ' }, { console: true, otlp: true }],
  ])('should honour an override that is %s', (_label, values, expected) => {
    // Arrange
    const environment = new OtelEnvironment(values);

    // Act
    const actual = selector.select(bothOn, 'OTEL_TRACES_EXPORTER', environment);

    // Assert
    actual.should.eql(expected);
  });
});

describe('ExporterSelector.selectAll', () => {
  it('should select per signal and switch off disabled signals', () => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_METRICS_EXPORTER: 'otlp' });

    // Act
    const actual = selector.selectAll(allOn, environment);

    // Assert
    actual.should.eql({
      logs: { console: true, otlp: true },
      metrics: { console: false, otlp: true },
      traces: { console: false, otlp: false },
    });
  });

  it('should switch every signal off when the SDK is disabled', () => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_SDK_DISABLED: 'true' });

    // Act
    const actual = selector.selectAll(allOn, environment);

    // Assert
    actual.should.eql({
      logs: { console: false, otlp: false },
      metrics: { console: false, otlp: false },
      traces: { console: false, otlp: false },
    });
    selector.live(allOn, environment).should.eql({ logs: false, metrics: false, traces: false });
  });
});
