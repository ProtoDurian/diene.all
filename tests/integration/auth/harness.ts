import { createHash } from 'node:crypto';
import { ProblemRegistry } from '@atomicloud/diene.problems';
import { Hono } from 'hono';
import type { TenantEnv } from '../../../src/adapters/auth/gate';
import { AuthModule } from '../../../src/adapters/auth/module';
import { PgDatabase } from '../../../src/adapters/db/database';
import type { IMcpNotesReader, McpNote } from '../../../src/adapters/mcp/server';
import type { IMailSender, MailMessage } from '../../../src/lib/auth/interfaces';
import type { AuthSettings, TenantApprovalMode } from '../../../src/lib/auth/structures';
import { PostgresFixture } from '../../support/postgres';

export const APP_URL = 'https://aseity.test';
export const MCP_URL = `${APP_URL}/mcp`;
const REDIRECT_URI = 'http://127.0.0.1:9999/callback';
// One secret per database: the JWT signing keys stored there are encrypted with it.
const AUTH_SECRET = createHash('sha256').update('aseity-integration-auth').digest('hex');

export class CapturingMailer implements IMailSender {
  readonly sent: MailMessage[] = [];

  async send(message: MailMessage): Promise<void> {
    this.sent.push(message);
  }

  lastOtp(to: string): string {
    const message = this.sent.filter(m => m.to === to).at(-1);
    const otp = /\b(\d{6})\b/.exec(message?.text ?? '')?.[1];
    if (!otp) throw new Error(`no OTP mailed to ${to}`);
    return otp;
  }
}

export class FixedNotes implements IMcpNotesReader {
  readonly byTenant = new Map<string, McpNote[]>();

  async list(tenantId: string): Promise<readonly McpNote[]> {
    return this.byTenant.get(tenantId) ?? [];
  }
}

export class AuthHarness {
  private constructor(
    readonly fixture: PostgresFixture,
    readonly db: PgDatabase,
    readonly module: AuthModule,
    readonly mailer: CapturingMailer,
    readonly notes: FixedNotes,
    readonly app: Hono<TenantEnv>,
  ) {}

  static async start(
    mode: TenantApprovalMode = 'manual',
    fixture?: PostgresFixture,
    overrides: Partial<AuthSettings> = {},
  ): Promise<AuthHarness> {
    const pg = fixture ?? (await PostgresFixture.start());
    const db = new PgDatabase({ connectionString: pg.connectionString });
    const mailer = new CapturingMailer();
    const notes = new FixedNotes();
    const registry = new ProblemRegistry({
      scheme: 'https',
      host: 'errors.aseity.test',
      landscape: 'test',
      platform: 'aseity',
      service: 'aseity',
      module: 'api',
    });
    const module = new AuthModule({
      db,
      settings: { appUrl: APP_URL, proxyUrl: APP_URL, secret: AUTH_SECRET, tenantApproval: mode, ...overrides },
      mailer,
      registry,
      notes,
    });
    const app = new Hono<TenantEnv>();
    module.routes.register(app);
    module.mcp.register(app);
    app.get('/api/notes', module.gate.handler, c => c.json(c.get('identity')));
    return new AuthHarness(pg, db, module, mailer, notes, app);
  }

  async request(path: string, init: RequestInit & { cookie?: string } = {}): Promise<Response> {
    const headers = new Headers(init.headers);
    headers.set('origin', APP_URL);
    if (init.cookie) headers.set('cookie', init.cookie);
    return this.app.request(`${APP_URL}${path}`, { ...init, headers });
  }

  async post(path: string, body: unknown, cookie?: string, headers: Record<string, string> = {}): Promise<Response> {
    return this.request(path, {
      method: 'POST',
      body: JSON.stringify(body),
      headers: { 'content-type': 'application/json', ...headers },
      ...(cookie ? { cookie } : {}),
    });
  }

  async signIn(email: string): Promise<string> {
    await this.post('/api/auth/email-otp/send-verification-otp', { email, type: 'sign-in' });
    const response = await this.post('/api/auth/sign-in/email-otp', { email, otp: this.mailer.lastOtp(email) });
    if (response.status !== 200) throw new Error(`sign-in failed: ${response.status} ${await response.text()}`);
    return this.cookies(response);
  }

  async createTenant(cookie: string, slug: string): Promise<string> {
    const response = await this.post('/api/auth/organization/create', { name: slug, slug }, cookie);
    if (response.status !== 200) throw new Error(`create org failed: ${response.status} ${await response.text()}`);
    return ((await response.json()) as { id: string }).id;
  }

  async approveTenant(tenantId: string): Promise<void> {
    await this.fixture.admin(client =>
      client.query(`UPDATE tenants SET status = 'approved' WHERE id = $1`, [tenantId]),
    );
  }

  // Dynamic registration, authorize, consent and token exchange, the way an MCP client signs in.
  async authorize(cookie: string): Promise<Response> {
    const registered = await this.post('/api/auth/oauth2/register', {
      redirect_uris: [REDIRECT_URI],
      token_endpoint_auth_method: 'none',
      client_name: 'test mcp client',
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
    });
    const client = (await registered.json()) as { client_id: string };
    const verifier = crypto.randomUUID() + crypto.randomUUID();
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
    const query = new URLSearchParams({
      response_type: 'code',
      client_id: client.client_id,
      redirect_uri: REDIRECT_URI,
      scope: 'openid profile',
      state: 'state',
      code_challenge: Buffer.from(digest).toString('base64url'),
      code_challenge_method: 'S256',
      resource: MCP_URL,
    });
    const authorized = await this.request(`/api/auth/oauth2/authorize?${query}`, { cookie });
    const location = authorized.headers.get('location') ?? '';
    if (!location.startsWith('/consent?')) return authorized;
    const consent = await this.post(
      '/api/auth/oauth2/consent',
      { accept: true, oauth_query: location.slice(9) },
      cookie,
    );
    const { url } = (await consent.json()) as { url: string };
    return this.request('/api/auth/oauth2/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: new URL(url).searchParams.get('code') as string,
        redirect_uri: REDIRECT_URI,
        client_id: client.client_id,
        code_verifier: verifier,
        resource: MCP_URL,
      }).toString(),
    });
  }

  async accessToken(cookie: string): Promise<string> {
    const response = await this.authorize(cookie);
    return ((await response.json()) as { access_token: string }).access_token;
  }

  async mcp(token: string | undefined, body: unknown): Promise<Response> {
    return this.request('/mcp', {
      method: 'POST',
      body: typeof body === 'string' ? body : JSON.stringify(body),
      headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    });
  }

  async makeAdmin(email: string): Promise<void> {
    await this.fixture.admin(client => client.query(`UPDATE "user" SET role = 'admin' WHERE email = $1`, [email]));
  }

  cookies(response: Response): string {
    return response.headers
      .getSetCookie()
      .map(cookie => cookie.split(';')[0])
      .join('; ');
  }

  async stop(): Promise<void> {
    await this.db.close();
    await this.fixture.stop();
  }
}
