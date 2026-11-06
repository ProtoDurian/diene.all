import { describe, it } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import type { UserRoleStore } from '../../../src/lib/admin/interfaces';
import { AdminGrantService } from '../../../src/lib/admin/service';
import type { AdminError, UserRole } from '../../../src/lib/admin/structures';

class MemoryUsers implements UserRoleStore {
  readonly users = new Map<string, UserRole>();
  failSet = false;

  find(email: string): Result<UserRole | undefined, AdminError> {
    return Ok([...this.users.values()].find(user => user.email === email));
  }

  setRole(userId: string, role: string): Result<void, AdminError> {
    if (this.failSet) return Err({ kind: 'store_failed', message: 'write refused' });
    const user = this.users.get(userId);
    if (user) this.users.set(userId, { ...user, role });
    return Ok(undefined);
  }
}

function setup(role?: string) {
  const users = new MemoryUsers();
  users.users.set('u1', role === undefined ? { id: 'u1', email: 'ada@example.com' } : { id: 'u1', email: 'ada@example.com', role });
  return { users, subject: new AdminGrantService(users) };
}

describe('AdminGrantService', () => {
  it('should make a user with no role an admin', async () => {
    // Arrange
    const { users, subject } = setup();

    // Act
    const actual = await expectOk(subject.grant('  Ada@Example.com '));

    // Assert
    actual.should.deepEqual({ email: 'ada@example.com', role: 'admin', changed: true });
    (users.users.get('u1')?.role ?? '').should.equal('admin');
  });

  it('should keep the roles a user already has', async () => {
    // Arrange
    const { users, subject } = setup('user, ');

    // Act
    const actual = await expectOk(subject.grant('ada@example.com'));

    // Assert
    actual.should.deepEqual({ email: 'ada@example.com', role: 'user,admin', changed: true });
    (users.users.get('u1')?.role ?? '').should.equal('user,admin');
  });

  it('should leave an existing admin unchanged', async () => {
    // Arrange
    const { users, subject } = setup('user,admin');
    users.failSet = true;

    // Act
    const actual = await expectOk(subject.grant('ada@example.com'));

    // Assert
    actual.should.deepEqual({ email: 'ada@example.com', role: 'user,admin', changed: false });
  });

  it.each(['', 'ada', 'ada@', 'a da@example.com'])('should refuse the email "%s"', async email => {
    // Arrange
    const { subject } = setup();

    // Act
    const actual = await expectErr(subject.grant(email));

    // Assert
    actual.should.deepEqual({ kind: 'invalid_email', email });
  });

  it('should report a user that has not signed up', async () => {
    // Arrange
    const { subject } = setup();

    // Act
    const actual = await expectErr(subject.grant('bob@example.com'));

    // Assert
    actual.should.deepEqual({ kind: 'user_not_found', email: 'bob@example.com' });
  });

  it('should report a failed role write', async () => {
    // Arrange
    const { users, subject } = setup();
    users.failSet = true;

    // Act
    const actual = await expectErr(subject.grant('ada@example.com'));

    // Assert
    actual.should.deepEqual({ kind: 'store_failed', message: 'write refused' });
  });
});
