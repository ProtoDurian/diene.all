import { afterAll, beforeAll, describe, it } from 'bun:test';
import 'should';
import { APP_URL, AuthHarness } from './harness';

let h: AuthHarness;
let tenantId: string;
let token: string;

beforeAll(async () => {
  h = await AuthHarness.start('manual');
  const cookie = await h.signIn('mcp@aseity.test');
  tenantId = await h.createTenant(cookie, 'mcp-co');
  token = await h.accessToken(cookie);
});

afterAll(async () => {
  await h.stop();
});

const rpc = (method: string, params?: Record<string, unknown>, id: number | null = 1) => ({
  jsonrpc: '2.0',
  ...(id === null ? {} : { id }),
  method,
  ...(params ? { params } : {}),
});

describe('MCP authentication', () => {
  it('should challenge a request without a bearer token', async () => {
    // Act
    const actual = await h.mcp(undefined, rpc('ping'));

    // Assert
    actual.status.should.equal(401);
    (actual.headers.get('www-authenticate') as string).should.equal(
      `Bearer resource_metadata="${APP_URL}/.well-known/oauth-protected-resource/mcp"`,
    );
  });

  it('should challenge a forged token', async () => {
    // Act
    const actual = await h.mcp('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln', rpc('ping'));

    // Assert
    actual.status.should.equal(401);
  });

  it('should refuse a token for a pending tenant with 403 tenant_pending', async () => {
    // Act
    const actual = await h.mcp(token, rpc('tools/list'));

    // Assert
    actual.status.should.equal(403);
    const problem = (await actual.json()) as { type: string; data: object };
    (problem.type.split('/').at(-1) as string).should.equal('tenant_pending');
    problem.data.should.deepEqual({ tenantId, status: 'pending' });
  });

  it('should send a user without an active tenant to tenant selection', async () => {
    // Arrange
    const cookie = await h.signIn('no-tenant@aseity.test');

    // Act
    const actual = await h.authorize(cookie);

    // Assert
    actual.status.should.equal(302);
    (actual.headers.get('location') as string).should.startWith('/select-tenant?');
  });
});

describe('MCP tools on an approved tenant', () => {
  beforeAll(async () => {
    await h.approveTenant(tenantId);
    h.notes.byTenant.set(tenantId, [
      { id: 'n1', title: 'first', body: 'one', createdAt: new Date('2026-03-15T14:30:00.000Z') },
      { id: 'n2', title: 'second', body: 'two', createdAt: '2026-03-16T09:00:00.000Z' },
    ]);
  });

  it.each([
    { requested: '2025-03-26', expected: '2025-03-26' },
    { requested: '1999-01-01', expected: '2025-06-18' },
    { requested: undefined, expected: '2025-06-18' },
  ])('should initialize with protocol $expected when $requested is asked', async ({ requested, expected }) => {
    // Act
    const actual = await h.mcp(token, rpc('initialize', requested ? { protocolVersion: requested } : {}));

    // Assert
    const body = (await actual.json()) as { result: { protocolVersion: string; serverInfo: { name: string } } };
    body.result.protocolVersion.should.equal(expected);
    body.result.serverInfo.name.should.equal('aseity');
  });

  it('should list the list_notes tool and answer ping', async () => {
    // Act
    const actual = await h.mcp(token, [rpc('tools/list', undefined, 1), rpc('ping', undefined, 2)]);

    // Assert
    const body = (await actual.json()) as [{ result: { tools: { name: string }[] } }, { result: object }];
    body[0].result.tools.map(tool => tool.name).should.deepEqual(['list_notes']);
    body[1].result.should.deepEqual({});
  });

  it("should list only the token tenant's notes as wire JSON", async () => {
    // Act
    const actual = await h.mcp(token, rpc('tools/call', { name: 'list_notes', arguments: {} }));

    // Assert
    const body = (await actual.json()) as { result: { structuredContent: object; content: { text: string }[] } };
    const expected = {
      items: [
        { id: 'n1', title: 'first', body: 'one', createdAt: '2026-03-15T14:30:00.000Z' },
        { id: 'n2', title: 'second', body: 'two', createdAt: '2026-03-16T09:00:00.000Z' },
      ],
    };
    body.result.structuredContent.should.deepEqual(expected);
    (JSON.parse((body.result.content[0] as { text: string }).text) as object).should.deepEqual(expected);
  });

  it.each([
    { label: 'an unknown tool', message: rpc('tools/call', { name: 'drop_tables' }), code: -32602 },
    { label: 'a call without params', message: rpc('tools/call'), code: -32602 },
    { label: 'an unknown method', message: rpc('resources/list'), code: -32601 },
    { label: 'a non JSON-RPC message', message: { id: 1, method: 'ping' }, code: -32600 },
    { label: 'a non-object message', message: [42], code: -32600 },
    { label: 'unparsable JSON', message: '{"jsonrpc":', code: -32700 },
  ])('should answer $label with JSON-RPC error $code', async ({ message, code }) => {
    // Act
    const actual = await h.mcp(token, message);

    // Assert
    const body = (await actual.json()) as { error?: { code: number } } | { error: { code: number } }[];
    const reply = Array.isArray(body) ? body[0] : body;
    (reply?.error?.code as number).should.equal(code);
  });

  it.each([
    { label: 'a notification', message: rpc('notifications/initialized', undefined, null) },
    { label: 'a batch of notifications', message: [rpc('notifications/initialized', undefined, null)] },
  ])('should accept $label with 202 and no body', async ({ message }) => {
    // Act
    const actual = await h.mcp(token, message);

    // Assert
    actual.status.should.equal(202);
    (await actual.text()).should.equal('');
  });

  it.each(['GET', 'DELETE'])('should refuse %s with 405', async method => {
    // Act
    const actual = await h.request('/mcp', { method, headers: { authorization: `Bearer ${token}` } });

    // Assert
    actual.status.should.equal(405);
    (actual.headers.get('allow') as string).should.equal('POST');
  });
});
