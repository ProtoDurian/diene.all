import { beforeAll, describe, it } from 'bun:test';
import 'should';
import { WorkerGraph, type WorkerModule } from '../../support/worker-graph';

// The Worker may reach Postgres only through the HYPERDRIVE binding, never a URL from anywhere else.
const ENV_READS = /\bprocess\.env\b|\bBun\.env\b|\bimport\.meta\.env\b/;
const URL_SOURCES = /\b(?:DATABASE_URL|POSTGRES_URL|PGHOST|PGUSER|PGPASSWORD|PGDATABASE)\b|postgres(?:ql)?:\/\//;
const DB_FACTORY_DIR = 'src/adapters/db/';
const DATABASE_CONSTRUCTION = /new PgDatabase\(([^)]*)\)/g;

describe('Worker database access', () => {
  let modules: readonly WorkerModule[];

  beforeAll(async () => {
    modules = await new WorkerGraph().modules();
  });

  it('should reach the database factory from the Worker entry', () => {
    // Assert
    modules.map(module => module.path).should.containEql('src/adapters/db/database.ts');
  });

  it('should never read the environment for a connection', () => {
    // Act
    const actual = modules.filter(module => ENV_READS.test(module.code)).map(module => module.path);

    // Assert
    actual.should.deepEqual([]);
  });

  it('should never name a database URL or a libpq variable', () => {
    // Act
    const actual = modules.filter(module => URL_SOURCES.test(module.code)).map(module => module.path);

    // Assert
    actual.should.deepEqual([]);
  });

  it('should open pg connections only inside the database factory', () => {
    // Act
    const actual = modules
      .filter(module => module.packages.includes('pg') && !module.path.startsWith(DB_FACTORY_DIR))
      .map(module => module.path);

    // Assert
    actual.should.deepEqual([]);
  });

  it('should build every database from the HYPERDRIVE binding', () => {
    // Act
    const sources = modules.flatMap(module => [...module.code.matchAll(DATABASE_CONSTRUCTION)].map(match => match[1]));

    // Assert
    sources.length.should.be.above(0);
    sources.should.matchEach('env.HYPERDRIVE');
  });
});
