import type { TenantPrincipal, TenantRecord } from './structures';

export interface IClock {
  now(): Date;
}

export interface IRandomSource {
  bytes(length: number): Uint8Array;
}

export interface ITenantRepository {
  create(id: string, record: TenantRecord): Promise<TenantPrincipal>;
  get(id: string): Promise<TenantPrincipal | undefined>;
  approve(id: string, approvedAt: Date): Promise<TenantPrincipal | undefined>;
}

export interface IMembershipRepository {
  isMember(userId: string, tenantId: string): Promise<boolean>;
}

export interface MailMessage {
  readonly to: string;
  readonly subject: string;
  readonly text: string;
  readonly html?: string;
}

export interface IMailSender {
  send(message: MailMessage): Promise<void>;
}
