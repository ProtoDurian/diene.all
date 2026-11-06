import { afterAll, beforeAll, beforeEach, describe, it } from 'bun:test';
import { randomUUID } from 'node:crypto';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { type NeonConnection, NeonBrancher } from '../../../src/adapters/fork/neon-brancher';
import { ForkNaming } from '../../../src/lib/fork/naming';

interface FakeBranch {
  id: string;
  name: string;
  parent_id?: string;
  checks: number;
}

// An in-memory stand-in for the Neon v2 API: branches become ready on their second status check.
class FakeNeon {
  readonly branches: FakeBranch[] = [];
  readonly calls: { method: string; path: string; auth: string | null; body: unknown }[] = [];
  readyAfter = 2;
  failWith: number | undefined;
  private server: ReturnType<typeof Bun.serve> | undefined;

  get url(): string {
    return `http://127.0.0.1:${this.server?.port}/api/v2`;
  }

  start(): void {
    this.server = Bun.serve({ port: 0, fetch: request => this.handle(request) });
  }

  stop(): void {
    this.server?.stop(true);
  }

  private async handle(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace('/api/v2/projects/proj-1', '');
    const body = request.method === 'POST' ? await request.json() : undefined;
    this.calls.push({ method: request.method, path, auth: request.headers.get('authorization'), body });
    if (this.failWith) return new Response('{"message":"boom"}', { status: this.failWith });
    if (request.method === 'GET' && path === '/branches') return Response.json({ branches: this.branches });
    if (request.method === 'POST' && path === '/branches') {
      const input = (body as { branch: { name: string; parent_id?: string } }).branch;
      const branch = { id: `br-${this.branches.length + 1}`, ...input, checks: 0 };
      this.branches.push(branch);
      return Response.json({ branch: { id: branch.id, name: branch.name, current_state: 'init' } });
    }
    if (path === '/connection_uri') {
      const q = url.searchParams;
      return Response.json({ uri: `postgres://${q.get('role_name')}@${q.get('branch_id')}.neon.test/${q.get('database_name')}` });
    }
    const id = path.replace('/branches/', '');
    const branch = this.branches.find(candidate => candidate.id === id);
    if (!branch) return new Response('{}', { status: 404 });
    if (request.method === 'DELETE') {
      this.branches.splice(this.branches.indexOf(branch), 1);
      return Response.json({ branch });
    }
    branch.checks++;
    const state = branch.checks >= this.readyAfter ? 'ready' : 'init';
    return Response.json({ branch: { id, name: branch.name, current_state: state } });
  }
}

describe('NeonBrancher (fake Neon API)', () => {
  const neon = new FakeNeon();
  let connection: NeonConnection;
  const naming = new ForkNaming({ database: 'app', bucket: 'files' });
  const apiKey = randomUUID();

  beforeAll(() => {
    neon.start();
    connection = {
      apiKey,
      projectId: 'proj-1',
      parentBranchId: 'br-main',
      databaseName: 'app',
      roleName: 'app_owner',
      baseUrl: neon.url,
      pollIntervalMs: 1,
      pollAttempts: 5,
    };
  });

  beforeEach(() => {
    neon.branches.length = 0;
    neon.calls.length = 0;
    neon.readyAfter = 2;
    neon.failWith = undefined;
  });

  afterAll(() => {
    neon.stop();
  });

  it('should branch from the parent, wait until ready and return its connection string', async () => {
    // Arrange
    const subject = new NeonBrancher(connection, naming);

    // Act
    const actual = await expectOk(subject.create('demo'));

    // Assert
    actual.should.deepEqual({ name: 'fork-demo', connectionString: 'postgres://app_owner@br-1.neon.test/app' });
    neon.calls.map(call => `${call.method} ${call.path}`).should.deepEqual([
      'GET /branches',
      'POST /branches',
      'GET /branches/br-1',
      'GET /branches/br-1',
      'GET /connection_uri',
    ]);
    neon.calls[1]?.body?.should.deepEqual({
      branch: { name: 'fork-demo', parent_id: 'br-main' },
      endpoints: [{ type: 'read_write' }],
    });
    neon.calls.every(call => call.auth === `Bearer ${apiKey}`).should.be.true();
  });

  it('should branch from the project default when no parent is set', async () => {
    // Arrange
    const { parentBranchId: _, ...rest } = connection;
    const subject = new NeonBrancher(rest, naming);

    // Act
    await expectOk(subject.create('demo'));

    // Assert
    neon.calls[1]?.body?.should.deepEqual({ branch: { name: 'fork-demo' }, endpoints: [{ type: 'read_write' }] });
  });

  it('should list fork branches and delete one by name', async () => {
    // Arrange
    const subject = new NeonBrancher(connection, naming);
    neon.branches.push({ id: 'br-main', name: 'main', checks: 0 }, { id: 'br-9', name: 'fork-demo', checks: 0 });

    // Act
    const listed = await expectOk(subject.list());
    await expectOk(subject.delete('demo'));

    // Assert
    listed.should.deepEqual(['demo']);
    neon.branches.map(branch => branch.name).should.deepEqual(['main']);
  });

  it('should refuse a branch that already exists and report a missing one', async () => {
    // Arrange
    const subject = new NeonBrancher(connection, naming);
    neon.branches.push({ id: 'br-9', name: 'fork-demo', checks: 0 });

    // Act
    const exists = await expectErr(subject.create('demo'));
    const missing = await expectErr(subject.delete('ghost'));

    // Assert
    exists.should.deepEqual({ kind: 'already_exists', name: 'demo' });
    missing.should.deepEqual({ kind: 'not_found', name: 'ghost' });
  });

  it('should give up on a branch that never becomes ready', async () => {
    // Arrange
    const subject = new NeonBrancher(connection, naming);
    neon.readyAfter = 99;

    // Act
    const actual = await expectErr(subject.create('slow'));

    // Assert
    actual.should.deepEqual({
      kind: 'provider_failed',
      step: 'database',
      message: 'Neon branch br-1 was not ready after 5 checks',
    });
  });

  it('should report an API failure', async () => {
    // Arrange
    const subject = new NeonBrancher(connection, naming);
    neon.failWith = 500;

    // Act
    const actual = await expectErr(subject.list());

    // Assert
    actual.should.deepEqual({
      kind: 'provider_failed',
      step: 'database',
      message: 'Neon GET /branches failed: 500 {"message":"boom"}',
    });
  });
});
