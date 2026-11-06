import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { AuthSettingsParser } from '../../../src/lib/auth/settings';

const SECRET = 'a'.repeat(32);
const BASE = { APP_URL: 'https://app.example.com/', BETTER_AUTH_SECRET: SECRET, TENANT_APPROVAL: 'manual' };

describe('AuthSettingsParser', () => {
  it('should parse the minimal env and default the proxy to the app url', async () => {
    // Arrange
    const subject = new AuthSettingsParser();

    // Act
    const actual = await expectOk(subject.parse(BASE));

    // Assert
    actual.should.deepEqual({
      appUrl: 'https://app.example.com',
      proxyUrl: 'https://app.example.com',
      secret: SECRET,
      tenantApproval: 'manual',
    });
  });

  it('should read the proxy url and both social providers', async () => {
    // Arrange
    const subject = new AuthSettingsParser();
    const env = {
      ...BASE,
      TENANT_APPROVAL: 'auto',
      OAUTH_PROXY_URL: 'https://auth.example.com//',
      GITHUB_CLIENT_ID: 'gh-id',
      GITHUB_CLIENT_SECRET: 'gh-secret',
      GOOGLE_CLIENT_ID: 'g-id',
      GOOGLE_CLIENT_SECRET: 'g-secret',
    };

    // Act
    const actual = await expectOk(subject.parse(env));

    // Assert
    actual.should.deepEqual({
      appUrl: 'https://app.example.com',
      proxyUrl: 'https://auth.example.com',
      secret: SECRET,
      tenantApproval: 'auto',
      github: { clientId: 'gh-id', clientSecret: 'gh-secret' },
      google: { clientId: 'g-id', clientSecret: 'g-secret' },
    });
  });

  it('should treat blank values as unset and drop a provider missing its secret', async () => {
    // Arrange
    const subject = new AuthSettingsParser();
    const env = { ...BASE, OAUTH_PROXY_URL: '', GITHUB_CLIENT_ID: 'gh-id', GITHUB_CLIENT_SECRET: '' };

    // Act
    const actual = await expectOk(subject.parse(env));

    // Assert
    actual.should.not.have.property('github');
    actual.proxyUrl.should.equal('https://app.example.com');
  });

  it.each([
    { field: 'TENANT_APPROVAL', value: 'sometimes' },
    { field: 'BETTER_AUTH_SECRET', value: 'short' },
    { field: 'APP_URL', value: 'not a url' },
  ])('should reject an invalid $field', async ({ field, value }) => {
    // Arrange
    const subject = new AuthSettingsParser();

    // Act
    const actual = await expectErr(subject.parse({ ...BASE, [field]: value }));

    // Assert
    actual.issues.map(issue => issue.path.join('.')).should.containEql(field);
  });
});
