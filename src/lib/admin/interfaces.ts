import type { Result } from '@atomicloud/diene.result';
import type { AdminError, UserRole } from './structures';

export interface UserRoleStore {
  find(email: string): Result<UserRole | undefined, AdminError>;
  setRole(userId: string, role: string): Result<void, AdminError>;
}
