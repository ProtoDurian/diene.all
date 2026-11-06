import { type FormEvent, useCallback, useEffect, useState } from 'react';
import { Button } from '../components/button.tsx';
import { ErrorSummary } from '../components/error-summary.tsx';
import { FailureScreen } from '../components/failure.tsx';
import { TextAreaField, TextField } from '../components/field.tsx';
import { useOnline } from '../components/offline-banner.tsx';
import { createNote, listNotes, type Note } from '../lib/api.ts';
import { isTenantPending, type Problem, problemTier } from '../lib/problem.ts';
import { navigate, useQueryParam } from '../lib/router.ts';
import { useDelayed } from '../lib/use-delayed.ts';
import { useDraft } from '../lib/use-draft.ts';
import { PendingScreen } from './pending.tsx';

const TITLE_MAX = 120;
const BODY_MAX = 5000;
const EMPTY_NOTE = { title: '', body: '' };
const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });

type Load = { state: 'loading' } | { state: 'ready'; notes: Note[] } | { state: 'error'; problem: Problem };
type NoteErrors = { title?: string | undefined; body?: string | undefined };

function validate(note: typeof EMPTY_NOTE): NoteErrors {
  return {
    title:
      note.title.trim() === ''
        ? 'Give the note a title.'
        : note.title.length > TITLE_MAX
          ? `Keep the title under ${TITLE_MAX} characters.`
          : undefined,
    body: note.body.length > BODY_MAX ? `Keep the note under ${BODY_MAX} characters.` : undefined,
  };
}

function summaryOf(errors: NoteErrors) {
  return (Object.entries(errors) as [string, string | undefined][])
    .filter((entry): entry is [string, string] => entry[1] !== undefined)
    .map(([field, message]) => ({ field: `note-${field}`, message }));
}

function serverFieldErrors(problem: Problem): NoteErrors {
  const first = (field: string) => problem.errors?.[field]?.[0];
  return { title: first('title'), body: first('body') };
}

function NoteForm({ onCreated }: { onCreated: (note: Note) => void }) {
  const [draft, setDraft, clearDraft] = useDraft('note', EMPTY_NOTE);
  const [submitted, setSubmitted] = useState(false);
  const [pending, setPending] = useState(false);
  const [serverErrors, setServerErrors] = useState<NoteErrors>({});
  const [serverMessage, setServerMessage] = useState<string | undefined>();
  const [summary, setSummary] = useState<ReturnType<typeof summaryOf>>([]);
  const live = validate(draft);
  const shown = (field: keyof NoteErrors) => serverErrors[field] ?? (submitted || draft[field] ? live[field] : undefined);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSubmitted(true);
    setServerErrors({});
    setServerMessage(undefined);
    const errors = summaryOf(live);
    setSummary(errors);
    if (errors.length > 0) return;
    setPending(true);
    const result = await createNote({ title: draft.title.trim(), body: draft.body });
    setPending(false);
    if (!result.ok) {
      const fieldErrors = serverFieldErrors(result.problem);
      setServerErrors(fieldErrors);
      setSummary(summaryOf(fieldErrors));
      setServerMessage(result.problem.detail ?? result.problem.title);
      return;
    }
    clearDraft();
    setSubmitted(false);
    setSummary([]);
    onCreated(result.value);
  };

  return (
    <form noValidate onSubmit={submit} className="flex flex-col gap-4">
      <ErrorSummary errors={summary} />
      {serverMessage && summary.length === 0 ? (
        <p role="alert" className="rounded-control border border-err-border bg-err-bg p-3 text-err">
          {serverMessage}
        </p>
      ) : null}
      <TextField
        id="note-title"
        label="Title"
        autoComplete="off"
        enterKeyHint="next"
        value={draft.title}
        error={shown('title')}
        onChange={event => setDraft({ title: event.target.value })}
      />
      <TextAreaField
        id="note-body"
        label="Note"
        enterKeyHint="enter"
        value={draft.body}
        error={shown('body')}
        hint={`${draft.body.length} / ${BODY_MAX}`}
        onChange={event => setDraft({ body: event.target.value })}
      />
      <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        {draft.title || draft.body ? (
          <Button variant="ghost" onClick={clearDraft}>
            Clear
          </Button>
        ) : null}
        <Button type="submit" variant="primary" pending={pending}>
          Save note
        </Button>
      </div>
    </form>
  );
}

function NotesSkeleton() {
  return (
    <ul aria-hidden="true" className="flex flex-col gap-2">
      {[0, 1, 2].map(row => (
        <li key={row} className="h-20 animate-pulse rounded-control bg-surface-2" />
      ))}
    </ul>
  );
}

export function NotesScreen({ tenantName, onSwitch }: { tenantName: string; onSwitch: () => void }) {
  const [load, setLoad] = useState<Load>({ state: 'loading' });
  const [query, setQuery] = useQueryParam('q');
  const online = useOnline();
  const showSkeleton = useDelayed(load.state === 'loading');

  const refresh = useCallback(async () => {
    setLoad({ state: 'loading' });
    const result = await listNotes();
    setLoad(result.ok ? { state: 'ready', notes: result.value } : { state: 'error', problem: result.problem });
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (online && load.state === 'error' && problemTier(load.problem) === 'retryable') void refresh();
  }, [online, load, refresh]);

  const signedOut = load.state === 'error' && load.problem.status === 401;
  useEffect(() => {
    if (signedOut) navigate('/sign-in', true);
  }, [signedOut]);

  if (load.state === 'error') {
    const { problem } = load;
    if (isTenantPending(problem)) return <PendingScreen tenantName={tenantName} onRetry={refresh} onSwitch={onSwitch} />;
    if (signedOut) return null;
    if (problemTier(problem) === 'failure') return <FailureScreen problem={problem} />;
  }

  const notes = load.state === 'ready' ? load.notes : [];
  const needle = query.trim().toLowerCase();
  const visible = needle
    ? notes.filter(note => `${note.title}\n${note.body}`.toLowerCase().includes(needle))
    : notes;

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)]">
      <section aria-labelledby="notes-title" className="flex min-w-0 flex-col gap-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <h1 id="notes-title" className="font-semibold text-xl">
            Notes
          </h1>
          <div className="sm:w-64">
            <TextField
              id="notes-search"
              label="Search notes"
              type="search"
              autoComplete="off"
              enterKeyHint="search"
              value={query}
              onChange={event => setQuery(event.target.value)}
            />
          </div>
        </div>

        {load.state === 'loading' ? (showSkeleton ? <NotesSkeleton /> : <div className="min-h-64" />) : null}

        {load.state === 'error' ? (
          <div role="alert" className="flex flex-col items-start gap-3 rounded-control border border-err-border bg-err-bg p-4 text-err">
            <p>
              {load.problem.title}. {load.problem.detail ?? 'Try again.'}
            </p>
            <Button onClick={refresh}>Try again</Button>
          </div>
        ) : null}

        {load.state === 'ready' && notes.length === 0 ? (
          <div className="rounded-panel border border-border border-dashed p-6 text-center">
            <p className="font-medium">No notes yet</p>
            <p className="text-fg-soft">Notes belong to this workspace only. Write your first one with the form.</p>
          </div>
        ) : null}

        {load.state === 'ready' && notes.length > 0 && visible.length === 0 ? (
          <div className="rounded-panel border border-border border-dashed p-6 text-center">
            <p className="font-medium">No notes match "{query}"</p>
            <Button variant="ghost" onClick={() => setQuery('')}>
              Clear search
            </Button>
          </div>
        ) : null}

        {visible.length > 0 ? (
          <ul className="flex flex-col gap-2">
            {visible.map(note => (
              <li key={note.id} className="rounded-control border border-border bg-surface p-4 shadow-control">
                <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <h2 className="break-words font-medium">{note.title}</h2>
                  <time dateTime={note.createdAt} className="text-muted text-sm">
                    {dateFormat.format(new Date(note.createdAt))}
                  </time>
                </div>
                {note.body ? <p className="mt-1 whitespace-pre-wrap break-words text-fg-soft">{note.body}</p> : null}
              </li>
            ))}
          </ul>
        ) : null}
      </section>

      <section aria-labelledby="new-note-title" className="flex flex-col gap-4 sm:rounded-panel sm:border sm:border-border sm:bg-surface sm:p-6 sm:shadow-panel lg:self-start">
        <h2 id="new-note-title" className="font-semibold text-lg">
          New note
        </h2>
        <NoteForm
          onCreated={note => setLoad(previous => ({ state: 'ready', notes: [note, ...(previous.state === 'ready' ? previous.notes : [])] }))}
        />
      </section>
    </div>
  );
}
