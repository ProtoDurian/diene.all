import { describe, it } from 'bun:test';
import { type ErrorPortalConfig, ProblemTypeUriBuilder } from '@atomicloud/diene.problems';
import 'should';
import { portal, thrown } from './support/fixtures';

describe('ProblemTypeUriBuilder', () => {
  it('should build the versioned type URI from every ErrorPortal segment', () => {
    // Arrange
    const builder = new ProblemTypeUriBuilder();
    const expected = 'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v7/entity_not_found';

    // Act
    const actual = builder.buildProblemTypeUri(portal, 'v7', 'entity_not_found');

    // Assert
    actual.should.equal(expected);
  });

  it('should place each segment and the version at its own position', () => {
    // Arrange
    const builder = new ProblemTypeUriBuilder();
    const config: ErrorPortalConfig = {
      scheme: 'http',
      host: 'localhost:8080',
      landscape: 'lapras',
      platform: 'alcohol',
      service: 'argon',
      module: 'billing.v2',
    };

    // Act
    const actual = builder.buildProblemTypeUri(config, 'v12', 'invalid_json');

    // Assert
    actual.should.equal('http://localhost:8080/docs/lapras/alcohol/argon/billing.v2/v12/invalid_json');
  });

  it('should keep the version in the URI so a version bump mints a new type', () => {
    // Arrange
    const builder = new ProblemTypeUriBuilder();

    // Act
    const first = builder.buildProblemTypeUri(portal, 'v1', 'conflict');
    const second = builder.buildProblemTypeUri(portal, 'v2', 'conflict');

    // Assert
    first.should.endWith('/v1/conflict');
    second.should.endWith('/v2/conflict');
    first.should.not.equal(second);
  });

  it('should reject hosts that are empty, carry URL components, or are not canonical', () => {
    // Arrange
    const builder = new ProblemTypeUriBuilder();
    const hosts = [
      '',
      ' errors.atomi.cloud',
      'errors.atomi.cloud/path',
      'user@errors.atomi.cloud',
      'errors.atomi.cloud?source=test',
      'errors.atomi.cloud#fragment',
      'errors.atomi.cloud:99999',
      'ERRORS.atomi.cloud',
      'errors.atomi.cloud:443',
    ];

    // Act
    const errors = hosts.map(host => thrown(() => builder.buildProblemTypeUri({ ...portal, host }, 'v1', 'conflict')));

    // Assert
    for (const error of errors) {
      error.should.be.instanceOf(RangeError);
    }
    errors[6]?.message.should.startWith('Invalid ErrorPortal host');
    errors[7]?.message.should.equal('ErrorPortal host is not a canonical host or host:port');
  });

  it('should reject each malformed service-tree segment, version, and id', () => {
    // Arrange
    const builder = new ProblemTypeUriBuilder();
    const cases: readonly [string, () => unknown][] = [
      ['landscape', () => builder.buildProblemTypeUri({ ...portal, landscape: '-raichu' }, 'v1', 'conflict')],
      ['platform', () => builder.buildProblemTypeUri({ ...portal, platform: 'nit/roso' }, 'v1', 'conflict')],
      ['service', () => builder.buildProblemTypeUri({ ...portal, service: '' }, 'v1', 'conflict')],
      ['module', () => builder.buildProblemTypeUri({ ...portal, module: 'a b' }, 'v1', 'conflict')],
      ['version', () => builder.buildProblemTypeUri(portal, '1', 'conflict')],
      ['version', () => builder.buildProblemTypeUri(portal, 'v0', 'conflict')],
      ['version', () => builder.buildProblemTypeUri(portal, 'v01', 'conflict')],
      ['id', () => builder.buildProblemTypeUri(portal, 'v1', 'EntityNotFound')],
    ];

    // Act
    const messages = cases.map(([, action]) => thrown(action).message);

    // Assert
    messages.map(message => message.split(' ')[0]).should.eql(cases.map(([segment]) => segment));
  });
});

describe('ProblemTypeUriBuilder scheme', () => {
  it('should refuse any scheme other than http or https at runtime', () => {
    // Arrange
    const builder = new ProblemTypeUriBuilder();
    const schemes = ['ftp', 'HTTPS', 'javascript', ''];

    // Act
    const errors = schemes.map(scheme =>
      thrown(() => builder.buildProblemTypeUri({ ...portal, scheme: scheme as 'https' }, 'v1', 'conflict')),
    );

    // Assert
    for (const error of errors) {
      error.should.be.instanceOf(RangeError);
      error.message.should.startWith('ErrorPortal scheme must be http or https');
    }
  });
});
