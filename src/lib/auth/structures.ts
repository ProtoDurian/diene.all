export type TenantStatus = 'pending' | 'approved' | 'suspended';

export type TenantApprovalMode = 'manual' | 'auto';

export type CredentialKind = 'session' | 'apiKey' | 'oauth';

export interface TenantRecord {
  readonly slug: string;
  readonly status: TenantStatus;
  readonly createdAt: Date;
  readonly approvedAt?: Date;
}

export interface TenantPrincipal {
  readonly id: string;
  readonly record: TenantRecord;
}

export interface OrganizationCreated {
  readonly id: string;
  readonly slug: string;
}

export interface Actor {
  readonly userId: string;
  readonly role?: string;
}

// What a credential claims before the tenant is checked.
export interface CredentialClaim {
  readonly via: CredentialKind;
  readonly userId?: string;
  readonly tenantId?: string;
}

// A caller allowed to act inside an approved tenant.
export interface TenantIdentity {
  readonly via: CredentialKind;
  readonly tenantId: string;
  readonly userId?: string;
}

export interface SocialProviderSettings {
  readonly clientId: string;
  readonly clientSecret: string;
}

export interface AuthSettings {
  readonly appUrl: string;
  readonly proxyUrl: string;
  readonly secret: string;
  readonly tenantApproval: TenantApprovalMode;
  readonly github?: SocialProviderSettings;
  readonly google?: SocialProviderSettings;
}
