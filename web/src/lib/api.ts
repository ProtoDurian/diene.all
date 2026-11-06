import { asProblem, offlineProblem, type Problem } from './problem.ts';

export type ApiResult<T> = { ok: true; value: T } | { ok: false; problem: Problem };

export type Note = {
  id: string;
  title: string;
  body: string;
  createdAt: string;
};

export type NewNote = Pick<Note, 'title' | 'body'>;

async function request<T>(path: string, init?: RequestInit): Promise<ApiResult<T>> {
  let response: Response;
  try {
    response = await fetch(path, {
      ...init,
      credentials: 'include',
      headers: { accept: 'application/json, application/problem+json', ...init?.headers },
    });
  } catch {
    return { ok: false, problem: offlineProblem() };
  }
  const body: unknown = await response.json().catch(() => undefined);
  if (!response.ok) return { ok: false, problem: asProblem(body, response.status) };
  return { ok: true, value: body as T };
}

export async function listNotes(): Promise<ApiResult<Note[]>> {
  const result = await request<{ items: Note[] }>('/api/notes');
  return result.ok ? { ok: true, value: result.value.items } : result;
}

export function createNote(note: NewNote): Promise<ApiResult<Note>> {
  return request<Note>('/api/notes', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(note),
  });
}
