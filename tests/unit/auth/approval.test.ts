import { describe, it } from 'bun:test';
import { expectErr, expectOk } from '@atomicloud/diene.result/test-helper';
import 'should';
import { TenantApprovalService } from '../../../src/lib/auth/approval';
import {
  NoActiveTenant,
  NotAdmin,
  NotAuthenticated,
  NotTenantMember,
  TenantNotApproved,
  TenantNotFound,
} from '../../../src/lib/auth/errors';
import type { IClock, IMembershipRepository, ITenantRepository } from '../../../src/lib/auth/interfaces';
import type { TenantPrincipal, TenantRecord, TenantStatus } from '../../../src/lib/auth/structures';

const NOW = new Date('2026-03-15T14:30:00.000Z');
const TENANT = '0190a6e0-0000-7000-8000-000000000001';

class FixedClock implements IClock {
  now(): Date {
    return NOW;
  }
}

class MemoryTenants implements ITenantRepository {
  readonly rows = new Map<string, TenantRecord>();

  async create(id: string, record: TenantRecord): Promise<TenantPrincipal> {
    this.rows.set(id, record);
    return { id, record };
  }

  async get(id: string): Promise<TenantPrincipal | undefined> {
    const record = this.rows.get(id);
    return record ? { id, record } : undefined;
  }

  async approve(id: string, approvedAt: Date): Promise<TenantPrincipal | undefined> {
    const record = this.rows.get(id);
    if (!record) return undefined;
    const approved: TenantRecord = { ...record, status: 'approved', approvedAt: record.approvedAt ?? approvedAt };
    this.rows.set(id, approved);
    return { id, record: approved };
  }

  seed(id: string, status: TenantStatus): void {
    this.rows.set(id, { slug: 'acme', status, createdAt: NOW });
  }
}

class MemoryMembers implements IMembershipRepository {
  constructor(private readonly members: ReadonlySet<string>) {}

  async isMember(userId: string, tenantId: string): Promise<boolean> {
    return this.members.has(`${userId}:${tenantId}`);
  }
}

const build = (mode: 'manual' | 'auto' = 'manual', members: string[] = [`alice:${TENANT}`]) => {
  const tenants = new MemoryTenants();
  const subject = new TenantApprovalService(mode, tenants, new MemoryMembers(new Set(members)), new FixedClock());
  return { tenants, subject };
};

describe('TenantApprovalService.register', () => {
  it('should create a pending tenant in manual mode', async () => {
    // Arrange
    const { subject } = build('manual');

    // Act
    const actual = await subject.register({ id: TENANT, slug: 'acme' });

    // Assert
    actual.should.deepEqual({ id: TENANT, record: { slug: 'acme', status: 'pending', createdAt: NOW } });
  });

  it('should create an approved tenant in auto mode', async () => {
    // Arrange
    const { subject } = build('auto');

    // Act
    const actual = await subject.register({ id: TENANT, slug: 'acme' });

    // Assert
    actual.should.deepEqual({
      id: TENANT,
      record: { slug: 'acme', status: 'approved', createdAt: NOW, approvedAt: NOW },
    });
  });
});

describe('TenantApprovalService.approve', () => {
  it('should approve a pending tenant for an admin', async () => {
    // Arrange
    const { subject, tenants } = build();
    tenants.seed(TENANT, 'pending');

    // Act
    const actual = await expectOk(subject.approve({ userId: 'root', role: 'user,admin' }, TENANT));

    // Assert
    actual.record.status.should.equal('approved');
    (actual.record.approvedAt as Date).should.equal(NOW);
  });

  it.each([
    { role: undefined, label: 'no role' },
    { role: 'user', label: 'user role' },
  ])('should refuse a caller with $label', async ({ role }) => {
    // Arrange
    const { subject, tenants } = build();
    tenants.seed(TENANT, 'pending');

    // Act
    const actual = await expectErr(subject.approve(role ? { userId: 'bob', role } : { userId: 'bob' }, TENANT));

    // Assert
    actual.should.be.instanceOf(NotAdmin);
    (tenants.rows.get(TENANT) as TenantRecord).status.should.equal('pending');
  });

  it('should report an unknown tenant', async () => {
    // Arrange
    const { subject } = build();

    // Act
    const actual = await expectErr(subject.approve({ userId: 'root', role: 'admin' }, TENANT));

    // Assert
    actual.should.be.instanceOf(TenantNotFound);
    (actual as TenantNotFound).tenantId.should.equal(TENANT);
  });
});

describe('TenantApprovalService.admit', () => {
  it('should admit a member of an approved tenant', async () => {
    // Arrange
    const { subject, tenants } = build();
    tenants.seed(TENANT, 'approved');

    // Act
    const actual = await expectOk(subject.admit({ via: 'session', userId: 'alice', tenantId: TENANT }));

    // Assert
    actual.should.deepEqual({ via: 'session', tenantId: TENANT, userId: 'alice' });
  });

  it('should admit a tenant API key without a user', async () => {
    // Arrange
    const { subject, tenants } = build();
    tenants.seed(TENANT, 'approved');

    // Act
    const actual = await expectOk(subject.admit({ via: 'apiKey', tenantId: TENANT }));

    // Assert
    actual.should.deepEqual({ via: 'apiKey', tenantId: TENANT });
  });

  it('should refuse a missing credential', async () => {
    // Arrange
    const { subject } = build();

    // Act
    const actual = await expectErr(subject.admit(undefined));

    // Assert
    actual.should.be.instanceOf(NotAuthenticated);
  });

  it('should refuse a credential without an active tenant', async () => {
    // Arrange
    const { subject } = build();

    // Act
    const actual = await expectErr(subject.admit({ via: 'session', userId: 'alice' }));

    // Assert
    actual.should.be.instanceOf(NoActiveTenant);
  });

  it('should refuse a user who is not a member', async () => {
    // Arrange
    const { subject, tenants } = build();
    tenants.seed(TENANT, 'approved');

    // Act
    const actual = await expectErr(subject.admit({ via: 'oauth', userId: 'mallory', tenantId: TENANT }));

    // Assert
    actual.should.be.instanceOf(NotTenantMember);
  });

  it.each([
    { status: 'pending' as const, expected: 'pending' },
    { status: 'suspended' as const, expected: 'suspended' },
    { status: undefined, expected: 'missing' },
  ])('should refuse a $expected tenant', async ({ status, expected }) => {
    // Arrange
    const { subject, tenants } = build();
    if (status) tenants.seed(TENANT, status);

    // Act
    const actual = await expectErr(subject.admit({ via: 'session', userId: 'alice', tenantId: TENANT }));

    // Assert
    actual.should.be.instanceOf(TenantNotApproved);
    (actual as TenantNotApproved).status.should.equal(expected);
  });
});

describe('TenantApprovalService.isAdmin', () => {
  it.each([
    { role: 'admin', expected: true },
    { role: ' user , admin ', expected: true },
    { role: 'administrator', expected: false },
    { role: undefined, expected: false },
  ])('should treat role "$role" as admin=$expected', ({ role, expected }) => {
    // Arrange
    const { subject } = build();

    // Act
    const actual = subject.isAdmin(role ? { userId: 'u', role } : { userId: 'u' });

    // Assert
    actual.should.equal(expected);
  });
});
