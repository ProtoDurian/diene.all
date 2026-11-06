import type { Result } from '@atomicloud/diene.result';
import type { DatabaseBrancher } from '../../lib/fork/interfaces';
import type { ForkNaming } from '../../lib/fork/naming';
import type { DatabaseBranch, ForkError } from '../../lib/fork/structures';
import { ForkFailure, ProviderAttempt } from './attempt';

export interface NeonConnection {
  readonly apiKey: string;
  readonly projectId: string;
  readonly parentBranchId?: string;
  readonly databaseName: string;
  readonly roleName: string;
  readonly baseUrl: string;
  readonly pollIntervalMs: number;
  readonly pollAttempts: number;
}

interface NeonBranch {
  readonly id: string;
  readonly name: string;
  readonly current_state?: string;
}

export class NeonBrancher implements DatabaseBrancher {
  constructor(
    private readonly connection: NeonConnection,
    private readonly naming: ForkNaming,
  ) {}

  private readonly attempt = new ProviderAttempt('database');

  create(fork: string): Result<DatabaseBranch, ForkError> {
    return this.attempt.run(async () => {
      const name = this.naming.branchName(fork);
      if ((await this.branches()).some(branch => branch.name === name)) {
        throw new ForkFailure({ kind: 'already_exists', name: fork });
      }
      const parent = this.connection.parentBranchId ? { parent_id: this.connection.parentBranchId } : {};
      const created = await this.request<{ branch: NeonBranch }>('POST', '/branches', {
        branch: { name, ...parent },
        endpoints: [{ type: 'read_write' }],
      });
      await this.waitUntilReady(created.branch.id);
      const query = new URLSearchParams({
        branch_id: created.branch.id,
        database_name: this.connection.databaseName,
        role_name: this.connection.roleName,
      });
      const uri = await this.request<{ uri: string }>('GET', `/connection_uri?${query}`);
      return { name, connectionString: uri.uri };
    });
  }

  list(): Result<readonly string[], ForkError> {
    return this.attempt.run(async () =>
      (await this.branches()).flatMap(branch => this.naming.branchFork(branch.name) ?? []),
    );
  }

  delete(fork: string): Result<void, ForkError> {
    return this.attempt.run(async () => {
      const name = this.naming.branchName(fork);
      const branch = (await this.branches()).find(candidate => candidate.name === name);
      if (!branch) throw new ForkFailure({ kind: 'not_found', name: fork });
      await this.request('DELETE', `/branches/${branch.id}`);
    });
  }

  private async waitUntilReady(id: string): Promise<void> {
    for (let attempt = 0; attempt < this.connection.pollAttempts; attempt++) {
      const { branch } = await this.request<{ branch: NeonBranch }>('GET', `/branches/${id}`);
      if (branch.current_state === 'ready') return;
      await new Promise(resolve => setTimeout(resolve, this.connection.pollIntervalMs));
    }
    throw new Error(`Neon branch ${id} was not ready after ${this.connection.pollAttempts} checks`);
  }

  private async branches(): Promise<NeonBranch[]> {
    return (await this.request<{ branches: NeonBranch[] }>('GET', '/branches')).branches;
  }

  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const response = await fetch(`${this.connection.baseUrl}/projects/${this.connection.projectId}${path}`, {
      method,
      headers: {
        accept: 'application/json',
        authorization: `Bearer ${this.connection.apiKey}`,
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`Neon ${method} ${path} failed: ${response.status} ${await response.text()}`);
    }
    return (await response.json()) as T;
  }
}
