import { describe, it } from 'bun:test';
import {
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_NAMESPACE,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';
import 'should';
import { OtelEnvironment } from '../../src/lib/environment';
import { type AppIdentity, ResourceIdentityMapper } from '../../src/lib/resource';

const identity: AppIdentity = {
  landscape: 'lapras',
  platform: 'atomi',
  service: 'diene',
  module: 'otel',
  version: '1.2.3',
};
const mapper = new ResourceIdentityMapper();
const semantic = {
  [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: 'lapras',
  [ATTR_SERVICE_NAMESPACE]: 'atomi',
  [ATTR_SERVICE_NAME]: 'diene',
  [ATTR_SERVICE_VERSION]: '1.2.3',
  'atomi.landscape': 'lapras',
  'atomi.module': 'otel',
  'atomi.platform': 'atomi',
  'atomi.service': 'diene',
  'atomi.version': '1.2.3',
};

describe('ResourceIdentityMapper.semantic', () => {
  it('should map the service-tree identity onto semconv and atomi.* attributes', () => {
    // Arrange
    const input = identity;

    // Act
    const actual = mapper.semantic(input);

    // Assert
    actual.should.eql(semantic);
    Object.isFrozen(actual).should.be.true();
  });

  it.each([
    ['a blank landscape', { ...identity, landscape: '' }],
    ['a whitespace service', { ...identity, service: '   ' }],
    ['an extra key', { ...identity, region: 'x' }],
  ])('should reject %s', (_label, input) => {
    // Arrange
    const candidate = input as AppIdentity;

    // Act
    const act = () => mapper.semantic(candidate);

    // Assert
    act.should.throw();
  });
});

describe('ResourceIdentityMapper.standard', () => {
  it.each([
    ['unset', undefined, {}],
    ['well-formed pairs', 'team=core, tier = gold', { team: 'core', tier: 'gold' }],
    ['malformed entries', 'novalue,=nokey, =x,,ok=1', { ok: '1' }],
    ['a value holding =', 'query=a=b', { query: 'a=b' }],
  ])('should parse OTEL_RESOURCE_ATTRIBUTES when %s', (_label, value, expected) => {
    // Arrange
    const environment = new OtelEnvironment({ OTEL_RESOURCE_ATTRIBUTES: value });

    // Act
    const actual = mapper.standard(environment);

    // Assert
    actual.should.eql(expected);
  });
});

describe('ResourceIdentityMapper.attributes', () => {
  it('should layer OTEL_RESOURCE_ATTRIBUTES then OTEL_SERVICE_NAME over the identity', () => {
    // Arrange
    const environment = new OtelEnvironment({
      OTEL_RESOURCE_ATTRIBUTES: `team=core,${ATTR_SERVICE_VERSION}=9.9.9`,
      OTEL_SERVICE_NAME: ' override ',
    });

    // Act
    const actual = mapper.attributes(identity, environment);

    // Assert
    actual.should.eql({ ...semantic, team: 'core', [ATTR_SERVICE_VERSION]: '9.9.9', [ATTR_SERVICE_NAME]: 'override' });
  });

  it('should build an OpenTelemetry resource carrying the attributes', () => {
    // Arrange
    const environment = new OtelEnvironment({});

    // Act
    const actual = mapper.resource(identity, environment);

    // Assert
    actual.attributes.should.eql(semantic);
  });
});
