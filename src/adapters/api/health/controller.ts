import type { Hono } from 'hono';
import type { IDatabase, IForkMarkerReader } from '../../../lib/db/interfaces';
import type { AppEnv, RouteModule } from '../env';
import type { ApiProblems } from '../problems';

export class HealthController implements RouteModule {
  constructor(
    private readonly db: IDatabase,
    private readonly fork: IForkMarkerReader,
    private readonly problems: ApiProblems,
  ) {}

  register(app: Hono<AppEnv>): void {
    app.get('/api/health', async c => {
      try {
        await this.db.withSystem(sql => sql.query('SELECT 1'));
        const marker = await this.fork.read();
        return c.json({ status: 'ok', fork: marker.isFork });
      } catch {
        return this.problems.serviceUnavailable('database');
      }
    });
  }
}
