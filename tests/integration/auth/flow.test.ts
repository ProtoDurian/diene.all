import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { getMigrations } from 'better-auth/db/migration';
import { AuthHarness } from './harness';

let h: AuthHarness;

beforeAll(async () => {
  h = await AuthHarness.start('manual');
});

afterAll(async () => {
  await h.stop();
});

const problemId = async (response: Response) => {
  const body = (await response.json()) as { type: string };
  return body.type.split('/').at(-1);
};

describe('auth schema migration', () => {
  it('should match every table and column the Better Auth options need', async () => {
    // Act
    const actual = await getMigrations(h.module.auth.options);

    // Assert
    actual.toBeCreated.map(table => table.table).should.deepEqual([]);
    actual.toBeAdded.map(table => table.table).should.deepEqual([]);
  });
});

describe('tenant approval (manual)', () => {
  it('should refuse a request without credentials with 401 unauthenticated', async () => {
    // Act
    const actual = await h.request('/api/notes');

    // Assert
    actual.status.should.equal(401);
    actual.headers.get('content-type')?.should.equal('application/problem+json');
    (await problemId(actual))?.should.equal('unauthenticated');
  });

  it('should refuse a signed-in user without an active tenant with 403 tenant_required', async () => {
    // Arrange
    const cookie = await h.signIn('lonely@aseity.test');

    // Act
    const actual = await h.request('/api/notes', { cookie });

    // Assert
    actual.status.should.equal(403);
    (await problemId(actual))?.should.equal('tenant_required');
  });

  it('should keep a new tenant pending until an admin approves it', async () => {
    // Arrange
    const owner = await h.signIn('owner@aseity.test');
    const tenantId = await h.createTenant(owner, 'acme');
    const pending = await h.request('/api/notes', { cookie: owner });
    const ownerApprove = await h.post(`/api/admin/tenants/${tenantId}/approve`, {}, owner);
    await h.signIn('root@aseity.test');
    await h.makeAdmin('root@aseity.test');
    const admin = await h.signIn('root@aseity.test');

    // Act
    const approved = await h.post(`/api/admin/tenants/${tenantId}/approve`, {}, admin);
    const allowed = await h.request('/api/notes', { cookie: owner });

    // Assert
    pending.status.should.equal(403);
    const problem = (await pending.json()) as { type: string; data: object };
    (problem.type.split('/').at(-1) as string).should.equal('tenant_pending');
    problem.data.should.deepEqual({ tenantId, status: 'pending' });
    ownerApprove.status.should.equal(403);
    (await problemId(ownerApprove))?.should.equal('forbidden');
    approved.status.should.equal(200);
    const tenant = (await approved.json()) as Record<string, string>;
    tenant.should.have.properties({ id: tenantId, slug: 'acme', status: 'approved' });
    tenant.approvedAt?.should.match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    allowed.status.should.equal(200);
    ((await allowed.json()) as object).should.deepEqual({ via: 'session', tenantId, userId: await userId(owner) });
  });

  it('should refuse a removed member of an approved tenant with 403 tenant_required', async () => {
    // Arrange
    const owner = await h.signIn('former@aseity.test');
    const tenantId = await h.createTenant(owner, 'former');
    await h.approveTenant(tenantId);
    await h.fixture.admin(client => client.query('DELETE FROM member WHERE "organizationId" = $1', [tenantId]));

    // Act
    const actual = await h.request('/api/notes', { cookie: owner });

    // Assert
    actual.status.should.equal(403);
    const problem = (await actual.json()) as { data: object };
    problem.data.should.deepEqual({ reason: 'not_member', tenantId });
  });

  it('should answer approve without a session with 401 and an unknown tenant with 404', async () => {
    // Arrange
    await h.signIn('root2@aseity.test');
    await h.makeAdmin('root2@aseity.test');
    const admin = await h.signIn('root2@aseity.test');

    // Act
    const anonymous = await h.post('/api/admin/tenants/0190a6e0-0000-7000-8000-000000000009/approve', {});
    const unknown = await h.post('/api/admin/tenants/0190a6e0-0000-7000-8000-000000000009/approve', {}, admin);
    const malformed = await h.post('/api/admin/tenants/not-a-uuid/approve', {}, admin);

    // Assert
    anonymous.status.should.equal(401);
    unknown.status.should.equal(404);
    (await problemId(unknown))?.should.equal('entity_not_found');
    malformed.status.should.equal(404);
  });

  it('should admit a tenant API key once the tenant is approved', async () => {
    // Arrange
    const owner = await h.signIn('keys@aseity.test');
    const tenantId = await h.createTenant(owner, 'keys');
    const created = await h.post('/api/auth/api-key/create', { organizationId: tenantId, name: 'ci' }, owner);
    const { key } = (await created.json()) as { key: string };
    const pending = await h.request('/api/notes', { headers: { 'x-api-key': key } });
    await h.approveTenant(tenantId);

    // Act
    const allowed = await h.request('/api/notes', { headers: { 'x-api-key': key } });
    const bogus = await h.request('/api/notes', { headers: { 'x-api-key': 'not-a-key' } });

    // Assert
    created.status.should.equal(200);
    pending.status.should.equal(403);
    allowed.status.should.equal(200);
    ((await allowed.json()) as object).should.deepEqual({ via: 'apiKey', tenantId });
    bogus.status.should.equal(401);
  });

  it('should mail the sign-in code through the app mailer', async () => {
    // Act
    await h.signIn('mail@aseity.test');

    // Assert
    const message = h.mailer.sent.filter(m => m.to === 'mail@aseity.test').at(-1);
    message?.subject.should.equal('Your aseity sign-in code');
  });
});

describe('tenant approval (auto)', () => {
  it('should approve a new tenant at once', async () => {
    // Arrange
    const auto = await AuthHarness.start('auto', h.fixture);
    const owner = await auto.signIn('auto@aseity.test');
    await auto.createTenant(owner, 'auto-co');

    // Act
    const actual = await auto.request('/api/notes', { cookie: owner });

    // Assert
    actual.status.should.equal(200);
    await auto.db.close();
  });
});

async function userId(cookie: string): Promise<string> {
  const response = await h.request('/api/auth/get-session', { cookie });
  return ((await response.json()) as { user: { id: string } }).user.id;
}

describe('discovery metadata', () => {
  it.each([
    '/.well-known/oauth-authorization-server',
    '/.well-known/oauth-authorization-server/api/auth',
    '/.well-known/openid-configuration',
    '/.well-known/openid-configuration/api/auth',
  ])('should publish the authorization server at %s', async path => {
    // Act
    const actual = await h.request(path);

    // Assert
    actual.status.should.equal(200);
    const body = (await actual.json()) as Record<string, unknown>;
    body.should.have.properties({
      issuer: 'https://aseity.test/api/auth',
      registration_endpoint: 'https://aseity.test/api/auth/oauth2/register',
    });
  });

  it.each(['/.well-known/oauth-protected-resource', '/.well-known/oauth-protected-resource/mcp'])(
    'should publish the MCP protected resource at %s',
    async path => {
      // Act
      const actual = await h.request(path);

      // Assert
      ((await actual.json()) as object).should.deepEqual({
        resource: 'https://aseity.test/mcp',
        authorization_servers: ['https://aseity.test/api/auth'],
        bearer_methods_supported: ['header'],
      });
    },
  );
});

describe('social sign-in through the OAuth proxy', () => {
  it.each(['github', 'google'])('should send %s back to the shared sign-in address', async provider => {
    // Arrange
    const social = await AuthHarness.start('manual', h.fixture, {
      proxyUrl: 'https://signin.aseity.test',
      github: { clientId: 'gh-client', clientSecret: 'gh-secret' },
      google: { clientId: 'g-client', clientSecret: 'g-secret' },
    });

    // Act
    const actual = await social.post('/api/auth/sign-in/social', { provider, callbackURL: '/' });

    // Assert
    const { url } = (await actual.json()) as { url: string };
    (new URL(url).searchParams.get('redirect_uri') as string).should.equal(
      `https://signin.aseity.test/api/auth/callback/${provider}`,
    );
    await social.db.close();
  });
});
