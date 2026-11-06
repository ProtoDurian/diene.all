import type { ProblemRegistry } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import type { ExecutionContext } from '@cloudflare/workers-types';
import type { z } from 'zod';
import type { Mailer } from '../../lib/mail/interfaces';
import type { IForkMarkerReader } from '../../lib/db/interfaces';
import { StorageSettingsParser } from '../../lib/files/service';
import { DEFAULT_DRAIN_OPTIONS, JobRunner, RetryPolicy } from '../../lib/jobs/service';
import type { DrainOptions, DrainSummary } from '../../lib/jobs/structures';
import { MailJobHandler, MailPolicy, MailSettingsParser } from '../../lib/mail/service';
import type { INotesReader } from '../../lib/notes/interfaces';
import { PgCachePurger } from '../data/cache/repo';
import { CachedForkMarkerReader, PgForkMarkerReader } from '../data/fork/reader';
import { PgJobStore } from '../data/jobs/repo';
import { PgNotesReader } from '../data/notes/repo';
import { type ConnectionSource, PgDatabase } from '../db/database';
import { PolicyMailer } from '../mail/policy-mailer';
import { SinkMailer } from '../mail/sink-mailer';
import { S3FileStore } from '../storage/s3-file-store';
import { ApiApp } from './app';
import type { IdentityGate, RouteModule } from './env';
import { HealthController } from './health/controller';
import { DeferredKicker } from './kicker';
import { NotesController } from './notes/controller';
import { ApiProblems, ProblemPortal } from './problems';
import { TenantTransaction } from './tenant-transaction';

export interface WorkerEnv {
  readonly HYPERDRIVE: ConnectionSource;
  readonly APP_URL: string;
  readonly [name: string]: unknown;
}

export type WaitUntil = Pick<ExecutionContext, 'waitUntil'>;

/** Everything one request or cron tick shares; built fresh each time because Worker I/O is per request. */
export interface RuntimeScope {
  readonly env: WorkerEnv;
  readonly db: PgDatabase;
  readonly registry: ProblemRegistry;
  readonly mailer: Mailer;
  readonly notes: INotesReader;
  readonly fork: IForkMarkerReader;
}

/** The auth seam: resolves who is calling and which tenant they act in. */
export interface AuthProvider {
  create(scope: RuntimeScope): Promise<{ readonly gate: IdentityGate; readonly modules: readonly RouteModule[] }>;
}

export interface RuntimeLog {
  info(message: string, fields: Record<string, unknown>): void;
  error(message: string, fields: Record<string, unknown>): void;
}

export interface RuntimeOptions {
  readonly drain?: DrainOptions;
  readonly mailEndpoint?: string;
  readonly log?: RuntimeLog;
}

class SettingsError extends Error {
  constructor(
    readonly block: string,
    readonly issues: readonly string[],
  ) {
    super(`invalid ${block} settings: ${issues.join('; ')}`);
    this.name = 'SettingsError';
  }
}

const SETUP_FAILURE = JSON.stringify({ type: 'about:blank', title: 'Internal Error', status: 500, data: {} });

export class WorkerRuntime {
  private readonly log: RuntimeLog;

  constructor(
    private readonly auth: AuthProvider,
    private readonly options: RuntimeOptions = {},
  ) {
    this.log = options.log ?? console;
  }

  async fetch(request: Request, env: WorkerEnv, ctx: WaitUntil): Promise<Response> {
    const db = new PgDatabase(env.HYPERDRIVE);
    const kicker = new DeferredKicker();
    let scope: RuntimeScope | undefined;
    try {
      scope = await this.scope(env, db);
      const problems = new ApiProblems(scope.registry);
      const { gate, modules } = await this.auth.create(scope);
      const files = new S3FileStore(await this.settings('storage', new StorageSettingsParser().parse(env)));
      const app = new ApiApp({
        problems,
        kicker,
        log: this.log,
        modules: [
          new HealthController(db, scope.fork, problems),
          ...modules,
          new NotesController({ problems, gate, transaction: new TenantTransaction(db), files, fork: scope.fork }),
        ],
      }).build();
      return await app.fetch(request);
    } catch (error) {
      this.log.error('request setup failed', { reason: String(error) });
      return new Response(SETUP_FAILURE, { status: 500, headers: { 'content-type': 'application/problem+json' } });
    } finally {
      ctx.waitUntil(this.afterResponse(db, kicker.wanted ? scope : undefined, false));
    }
  }

  async scheduled(env: WorkerEnv, ctx: WaitUntil): Promise<void> {
    const db = new PgDatabase(env.HYPERDRIVE);
    try {
      const scope = await this.scope(env, db);
      ctx.waitUntil(this.afterResponse(db, scope, true));
    } catch (error) {
      this.log.error('scheduled setup failed', { reason: String(error) });
      ctx.waitUntil(db.close());
    }
  }

  private async afterResponse(db: PgDatabase, drainScope: RuntimeScope | undefined, purge: boolean): Promise<void> {
    try {
      if (drainScope !== undefined) {
        const summary = await this.drain(drainScope);
        this.log.info('jobs drained', { ...summary });
      }
      if (purge) await new PgCachePurger(db).purgeExpired();
    } catch (error) {
      this.log.error('background work failed', { reason: String(error) });
    } finally {
      await db.close();
    }
  }

  private async drain(scope: RuntimeScope): Promise<DrainSummary> {
    const fork = await scope.fork.read();
    const runner = new JobRunner(
      new PgJobStore(scope.db),
      [new MailJobHandler(scope.mailer)],
      new RetryPolicy(),
      fork.isFork,
      this.options.drain ?? DEFAULT_DRAIN_OPTIONS,
    );
    return runner.drain();
  }

  private async scope(env: WorkerEnv, db: PgDatabase): Promise<RuntimeScope> {
    const fork = new CachedForkMarkerReader(new PgForkMarkerReader(db));
    const mailSettings = await this.settings('mail', new MailSettingsParser().parse(env));
    const mailer = new PolicyMailer(
      new MailPolicy(),
      mailSettings,
      fork,
      new SinkMailer(this.log),
      this.options.mailEndpoint,
    );
    return {
      env,
      db,
      fork,
      mailer,
      registry: new ProblemPortal().registry(env.APP_URL),
      notes: new PgNotesReader(db),
    };
  }

  private settings<T>(block: string, parsed: Result<T, z.ZodError>): Promise<T> {
    return parsed.match({
      ok: value => value,
      err: error => {
        throw new SettingsError(
          block,
          error.issues.map(issue => `${issue.path.join('.')} ${issue.message}`),
        );
      },
    });
  }
}
