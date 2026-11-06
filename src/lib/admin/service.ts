import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { UserRoleStore } from './interfaces';
import type { AdminError, AdminGranted, UserRole } from './structures';

const ADMIN = 'admin';
const EMAIL = /^[^\s@]+@[^\s@]+$/;

// Better Auth's admin plugin keeps a user's roles as one comma-separated string.
export class AdminGrantService {
  constructor(private readonly users: UserRoleStore) {}

  grant(raw: string): Result<AdminGranted, AdminError> {
    const email = raw.trim().toLowerCase();
    if (!EMAIL.test(email)) return Err({ kind: 'invalid_email', email: raw });
    return this.users
      .find(email)
      .andThen(user => (user ? Ok<UserRole, AdminError>(user) : Err<UserRole, AdminError>({ kind: 'user_not_found', email })))
      .andThen(user => this.promote(user));
  }

  private promote(user: UserRole): Result<AdminGranted, AdminError> {
    const roles = (user.role ?? '')
      .split(',')
      .map(role => role.trim())
      .filter(role => role.length > 0);
    if (roles.includes(ADMIN)) return Ok({ email: user.email, role: roles.join(','), changed: false });
    const role = [...roles, ADMIN].join(',');
    return this.users.setRole(user.id, role).map(() => ({ email: user.email, role, changed: true }));
  }
}
