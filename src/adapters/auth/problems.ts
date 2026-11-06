import {
  createProblem,
  EntityNotFound,
  type ProblemDefinition,
  type ProblemRegistry,
  type RegisteredProblem,
} from '@atomicloud/diene.problems';
import { z } from 'zod';
import {
  type AdmissionError,
  type ApprovalError,
  NoActiveTenant,
  NotAdmin,
  NotAuthenticated,
  NotTenantMember,
  type TenantNotApproved,
} from '../../lib/auth/errors';

const VERSION = 'v1';

const Unauthenticated = {
  id: 'unauthenticated',
  title: 'Unauthenticated',
  status: 401,
  version: VERSION,
  dataSchema: z.object({}).strict(),
};

const TenantPending = {
  id: 'tenant_pending',
  title: 'Tenant Pending Approval',
  status: 403,
  version: VERSION,
  dataSchema: z.object({ tenantId: z.string(), status: z.enum(['pending', 'suspended', 'missing']) }).strict(),
};

const TenantRequired = {
  id: 'tenant_required',
  title: 'Tenant Required',
  status: 403,
  version: VERSION,
  dataSchema: z
    .object({ reason: z.enum(['no_active_tenant', 'not_member']), tenantId: z.string().optional() })
    .strict(),
};

const Forbidden = {
  id: 'forbidden',
  title: 'Forbidden',
  status: 403,
  version: VERSION,
  dataSchema: z.object({ reason: z.string() }).strict(),
};

export class AuthProblems {
  private readonly unauthenticated: RegisteredProblem<typeof Unauthenticated.dataSchema>;
  private readonly tenantPending: RegisteredProblem<typeof TenantPending.dataSchema>;
  private readonly tenantRequired: RegisteredProblem<typeof TenantRequired.dataSchema>;
  private readonly forbidden: RegisteredProblem<typeof Forbidden.dataSchema>;
  private readonly notFound: RegisteredProblem<typeof EntityNotFound.dataSchema>;

  constructor(registry: ProblemRegistry) {
    this.unauthenticated = this.ensure(registry, Unauthenticated);
    this.tenantPending = this.ensure(registry, TenantPending);
    this.tenantRequired = this.ensure(registry, TenantRequired);
    this.forbidden = this.ensure(registry, Forbidden);
    this.notFound = this.ensure(registry, { ...EntityNotFound, version: VERSION });
  }

  admission(error: AdmissionError): Response {
    if (error instanceof NotAuthenticated) return this.respond(createProblem(this.unauthenticated, { data: {} }));
    if (error instanceof NoActiveTenant) {
      return this.respond(
        createProblem(this.tenantRequired, { detail: error.message, data: { reason: 'no_active_tenant' } }),
      );
    }
    if (error instanceof NotTenantMember) {
      return this.respond(
        createProblem(this.tenantRequired, {
          detail: error.message,
          data: { reason: 'not_member', tenantId: error.tenantId },
        }),
      );
    }
    return this.respond(this.pending(error));
  }

  approval(error: ApprovalError): Response {
    if (error instanceof NotAdmin) {
      return this.respond(createProblem(this.forbidden, { detail: error.message, data: { reason: 'admin_required' } }));
    }
    return this.respond(
      createProblem(this.notFound, { detail: error.message, data: { entityType: 'tenant', id: error.tenantId } }),
    );
  }

  unauthenticatedResponse(headers?: Record<string, string>): Response {
    return this.respond(createProblem(this.unauthenticated, { data: {} }), headers);
  }

  private pending(error: TenantNotApproved) {
    return createProblem(this.tenantPending, {
      detail: error.message,
      data: { tenantId: error.tenantId, status: error.status },
    });
  }

  private respond(problem: { status: number }, headers?: Record<string, string>): Response {
    const response = new Response(JSON.stringify(problem), {
      status: problem.status,
      headers: { 'content-type': 'application/problem+json' },
    });
    for (const [name, value] of Object.entries(headers ?? {})) response.headers.set(name, value);
    return response;
  }

  private ensure<TSchema extends z.ZodType>(
    registry: ProblemRegistry,
    definition: ProblemDefinition<TSchema>,
  ): RegisteredProblem<TSchema> {
    return (
      (registry.get(definition.id, definition.version) as RegisteredProblem<TSchema> | undefined) ??
      registry.register(definition)
    );
  }
}
