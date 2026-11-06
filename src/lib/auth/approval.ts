import { Err, Ok, type Result } from '@atomicloud/diene.result';
import {
  type AdmissionError,
  type ApprovalError,
  NoActiveTenant,
  NotAdmin,
  NotAuthenticated,
  NotTenantMember,
  TenantNotApproved,
  TenantNotFound,
} from './errors';
import type { IClock, IMembershipRepository, ITenantRepository } from './interfaces';
import type {
  Actor,
  CredentialClaim,
  OrganizationCreated,
  TenantApprovalMode,
  TenantIdentity,
  TenantPrincipal,
} from './structures';

export class TenantApprovalService {
  constructor(
    private readonly mode: TenantApprovalMode,
    private readonly tenants: ITenantRepository,
    private readonly members: IMembershipRepository,
    private readonly clock: IClock,
  ) {}

  async register(organization: OrganizationCreated): Promise<TenantPrincipal> {
    const createdAt = this.clock.now();
    const record =
      this.mode === 'auto'
        ? { slug: organization.slug, status: 'approved' as const, createdAt, approvedAt: createdAt }
        : { slug: organization.slug, status: 'pending' as const, createdAt };
    return this.tenants.create(organization.id, record);
  }

  approve(actor: Actor, tenantId: string): Result<TenantPrincipal, ApprovalError> {
    if (!this.isAdmin(actor)) return Err(new NotAdmin(actor.userId));
    return Ok<TenantPrincipal | undefined, ApprovalError>(this.tenants.approve(tenantId, this.clock.now())).andThen(
      tenant => (tenant ? Ok(tenant) : Err(new TenantNotFound(tenantId))),
    );
  }

  admit(claim: CredentialClaim | undefined): Result<TenantIdentity, AdmissionError> {
    if (!claim) return Err(new NotAuthenticated());
    const { tenantId, userId, via } = claim;
    if (!tenantId) return Err(new NoActiveTenant());
    return Ok<boolean, AdmissionError>(userId ? this.members.isMember(userId, tenantId) : true)
      .andThen(member =>
        member
          ? Ok<TenantPrincipal | undefined, AdmissionError>(this.tenants.get(tenantId))
          : Err<TenantPrincipal | undefined, AdmissionError>(new NotTenantMember(tenantId)),
      )
      .andThen(tenant => {
        const status = tenant?.record.status ?? 'missing';
        if (status !== 'approved') return Err(new TenantNotApproved(tenantId, status));
        return Ok(userId ? { via, tenantId, userId } : { via, tenantId });
      });
  }

  isAdmin(actor: Actor): boolean {
    return (actor.role ?? '').split(',').some(role => role.trim() === 'admin');
  }
}
