# Testing in TypeScript/Bun

## Framework: `bun:test` + `should`

Bun test runner with `should` assertion library.

## Test Structure: describe / it

```typescript
import { describe, it, beforeEach } from 'bun:test';
import '../setup.ts';
import should from 'should';

describe('UserService', () => {
  let mockRepo: IUserRepository;
  let subject: UserService;

  beforeEach(() => {
    mockRepo = {
      /* ... */
    };
    subject = new UserService(mockRepo);
  });

  it('should create user with valid input', async () => {
    // Arrange
    const input: UserRecord = { name: 'Alice', email: 'alice@test.com' };
    const expected = 'Alice';

    // Act
    const actual = await subject.create(input);

    // Assert
    actual.principal.record.name.should.equal(expected);
  });
});
```

## Arrange / Act / Assert

House convention: every test body is up to three blocks, each opened by its
marker comment and separated by a blank line. Leave out a block that would be
empty, together with its marker.

```typescript
it('should compose a namespaced key', () => {
  // Arrange
  const subject = new KeyComposer('Bun Base');

  // Act
  const actual = subject.compose('Sample Key');

  // Assert
  actual.should.equal('bun-base:sample-key');
});
```

## Assertions (should)

Prototype form everywhere: the value first, then `.should`. `should(value)` is
only for `null` and `undefined`, which have no prototype.

| Check            | Write                                                     | Never                                 |
| ---------------- | --------------------------------------------------------- | ------------------------------------- |
| strict equality  | `actual.should.equal(expected)`                           | `should(actual).equal(expected)`      |
| deep equality    | `actual.should.deepEqual(expected)`                       | `should(actual).eql(expected)`        |
| boolean          | `result.should.be.true()`                                 | `should(result).be.true()`            |
| defined          | `value.should.not.be.undefined()`                         | `should(value).not.be.undefined()`    |
| null / undefined | `should(value).be.null()`, `should(value).be.undefined()` | `value.should.be.null()`              |
| throws           | `act.should.throw(ErrorType)`                             | `should(act).throw(ErrorType)`        |
| rejects          | `await promise.should.be.rejectedWith(ErrorType)`         | `await should(promise).be.rejected()` |

Import `'should'` for its side effect; import the default only when a test
calls `should(...)`:

```typescript
import 'should'; // prototype assertions only
import should from 'should'; // also asserts null or undefined
```

More prototype assertions:

```typescript
value.should.be.ok(); // truthy
count.should.be.within(1, 10);
text.should.containEql('substring');
items.should.have.length(3);
obj.should.have.property('key', 'value');
value.should.be.a.String();
actual.should.not.equal(other);
```

## Parameterized Tests — `it.each`

```typescript
import { describe, it } from 'bun:test';
import 'should';

describe('StatusFormatter', () => {
  it.each([
    { input: 'pending', expected: 'Pending' },
    { input: 'running', expected: 'Running' },
    { input: 'completed', expected: 'Completed' },
  ])('should format status "$input" as "$expected"', async ({ input, expected }) => {
    // Arrange
    const subject = new StatusFormatter();

    // Act
    const actual = subject.format(input);

    // Assert
    actual.should.equal(expected);
  });
});
```

## Manual Mocks

Implement the interface directly:

```typescript
class MemoryFileSystem implements IFileSystemAdapter {
  private readonly files = new Map<string, string>();

  async readFile(path: string): Promise<string> {
    const content = this.files.get(path);
    if (content === undefined) throw new Error(`File not found: ${path}`);
    return content;
  }

  async writeFile(path: string, content: string): Promise<void> {
    this.files.set(path, content);
  }

  async exists(path: string): Promise<boolean> {
    return this.files.has(path);
  }
}
```

## Spy Patterns

```typescript
// Collect calls
const logged: string[] = [];
const spyLogger: ILogger = {
  log: (msg: string) => logged.push(msg),
};
// Assert: logged.should.deepEqual(['msg1', 'msg2']);

// Capture argument
let captured: any = null;
const mockSender: ISender = {
  send: (payload: any) => {
    captured = payload;
  },
};
// Assert: captured.should.have.property('id', '123');

// Count calls
let count = 0;
const mockClient: IClient = {
  fetch: () => {
    count++;
    throw new Error('fail');
  },
};
// Assert: count.should.equal(3);
```

## Functional Test — Contract Test

```typescript
import { describe, it, beforeEach } from 'bun:test';
import should from 'should';

function repoContractTests(name: string, createRepo: () => ITaskRepository) {
  describe(`ITaskRepository contract: ${name}`, () => {
    let subject: ITaskRepository;

    beforeEach(() => {
      subject = createRepo();
    });

    it('should save and retrieve by id', async () => {
      // Arrange
      const input = createTestTask();

      // Act
      await subject.save(input);
      const actual = await subject.findById(input.id);

      // Assert
      should(actual).not.be.null();
      actual!.name.should.equal(input.name);
    });
  });
}

repoContractTests('MemoryRepo', () => new TaskMemoryRepo());
repoContractTests('FileRepo', () => new TaskFileRepo(mockFs, mapper, '/tmp/test.json'));
```

## Integration Test — Testcontainers

```typescript
import { describe, it, beforeEach, afterEach } from 'bun:test';
import should from 'should';
import { GenericContainer, StartedTestContainer } from 'testcontainers';

describe('PostRepository (Postgres)', () => {
  let container: StartedTestContainer;
  let pool: Pool;
  let subject: PostRepository;

  beforeEach(async () => {
    container = await new GenericContainer('postgres:16')
      .withExposedPorts(5432)
      .withEnvironment({ POSTGRES_PASSWORD: 'test', POSTGRES_DB: 'testdb' })
      .start();

    pool = new Pool({
      host: container.getHost(),
      port: container.getMappedPort(5432),
      user: 'postgres',
      password: 'test',
      database: 'testdb',
    });

    await pool.query(`CREATE TABLE posts (id TEXT PRIMARY KEY, title TEXT)`);
    subject = new PostRepository(pool, new PostRepoMapper());
  });

  afterEach(async () => {
    await pool.end();
    await container.stop();
  });

  it('should persist and retrieve a post', async () => {
    // Arrange
    const input = { title: 'Test Post', description: 'A test', tags: ['test'] };

    // Act
    const created = await subject.create(input);
    const actual = await subject.get(created.principal.id);

    // Assert
    should(actual).not.be.null();
    actual!.principal.record.title.should.equal('Test Post');
  });
});
```

## Test Folder Structure

| Test Type   | Location             |
| ----------- | -------------------- |
| Unit        | `tests/unit/`        |
| Functional  | `tests/unit/`        |
| Integration | `tests/integration/` |
