import type { TenantStatus } from './structures';

export class NotAuthenticated extends Error {
  constructor() {
    super('No valid session, API key or access token');
    this.name = 'NotAuthenticated';
  }
}

export class NoActiveTenant extends Error {
  constructor() {
    super('The credential has no active tenant');
    this.name = 'NoActiveTenant';
  }
}

export class NotTenantMember extends Error {
  constructor(readonly tenantId: string) {
    super(`Not a member of tenant ${tenantId}`);
    this.name = 'NotTenantMember';
  }
}

export class TenantNotApproved extends Error {
  constructor(
    readonly tenantId: string,
    readonly status: Exclude<TenantStatus, 'approved'> | 'missing',
  ) {
    super(`Tenant ${tenantId} is ${status}`);
    this.name = 'TenantNotApproved';
  }
}

export class TenantNotFound extends Error {
  constructor(readonly tenantId: string) {
    super(`Tenant not found: ${tenantId}`);
    this.name = 'TenantNotFound';
  }
}

export class NotAdmin extends Error {
  constructor(readonly userId: string) {
    super(`User ${userId} is not an admin`);
    this.name = 'NotAdmin';
  }
}

export type AdmissionError = NotAuthenticated | NoActiveTenant | NotTenantMember | TenantNotApproved;

export type ApprovalError = NotAdmin | TenantNotFound;
