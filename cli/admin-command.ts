import type { AdminGrantService } from '../src/lib/admin/service';
import type { AdminError } from '../src/lib/admin/structures';
import type { Output } from './output';

export class AdminCommand {
  constructor(
    private readonly service: AdminGrantService,
    private readonly output: Output,
  ) {}

  async grant(email: string): Promise<number> {
    return this.service.grant(email).match({
      ok: granted => {
        const human = granted.changed
          ? `${granted.email} is now an admin (roles: ${granted.role}); they get it on their next sign-in`
          : `${granted.email} is already an admin`;
        this.output.result(human, granted);
        return 0;
      },
      err: error => {
        this.output.error(this.describe(error), error);
        return 1;
      },
    });
  }

  private describe(error: AdminError): string {
    switch (error.kind) {
      case 'invalid_email':
        return `'${error.email}' is not an email address`;
      case 'user_not_found':
        return `no user signed up with ${error.email}; sign in once, then grant`;
      case 'store_failed':
        return `database step failed: ${error.message}`;
    }
  }
}
