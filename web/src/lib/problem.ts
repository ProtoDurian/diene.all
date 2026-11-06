export type Problem = {
  type: string;
  title: string;
  status: number;
  detail?: string;
  instance?: string;
  errors?: Record<string, string[]>;
};

export type ProblemTier = 'retryable' | 'actionable' | 'failure';

const RETRYABLE_STATUSES = new Set([0, 408, 425, 429, 502, 503, 504]);

export function problemTier(problem: Problem): ProblemTier {
  if (RETRYABLE_STATUSES.has(problem.status)) return 'retryable';
  if (problem.status >= 400 && problem.status < 500) return 'actionable';
  return 'failure';
}

function problemId(problem: Problem): string {
  const segments = problem.type.split(/[/#]/).filter(segment => segment.length > 0);
  return segments.at(-1) ?? '';
}

export function isTenantPending(problem: Problem): boolean {
  return problem.status === 403 && problemId(problem) === 'tenant_pending';
}

export function offlineProblem(): Problem {
  return {
    type: 'about:blank',
    title: 'You are offline',
    status: 0,
    detail: 'Check your connection. We will retry when you are back online.',
  };
}

export function asProblem(value: unknown, status: number): Problem {
  if (typeof value === 'object' && value !== null && 'title' in value && typeof value.title === 'string') {
    const candidate = value as Partial<Problem>;
    return {
      ...candidate,
      type: typeof candidate.type === 'string' ? candidate.type : 'about:blank',
      title: value.title,
      status: typeof candidate.status === 'number' ? candidate.status : status,
    };
  }
  return { type: 'about:blank', title: 'Unexpected response', status };
}
