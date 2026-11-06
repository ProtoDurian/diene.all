import { type FormEvent, useState } from 'react';
import { Button } from '../components/button.tsx';
import { ErrorSummary } from '../components/error-summary.tsx';
import { TextField } from '../components/field.tsx';
import { authClient } from '../lib/auth-client.ts';
import { useDraft } from '../lib/use-draft.ts';

const EMPTY_DRAFT = { name: '' };

function slugify(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
}

function nameError(name: string): string | undefined {
  if (name.trim().length < 2) return 'Give the workspace a name of at least 2 characters.';
  return slugify(name) === '' ? 'Use at least one letter or number in the name.' : undefined;
}

export function CreateTenantForm({ onCreated, onCancel }: { onCreated: () => void; onCancel?: () => void }) {
  const [draft, setDraft, clearDraft] = useDraft('create-tenant', EMPTY_DRAFT);
  const [touched, setTouched] = useState(false);
  const [pending, setPending] = useState(false);
  const [serverError, setServerError] = useState<string | undefined>();
  const error = touched ? nameError(draft.name) : undefined;

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setTouched(true);
    if (nameError(draft.name)) return;
    setPending(true);
    setServerError(undefined);
    const result = await authClient.organization.create({ name: draft.name.trim(), slug: slugify(draft.name) });
    if (result.error || !result.data) {
      setPending(false);
      setServerError(result.error?.message ?? 'We could not create the workspace. Try again.');
      return;
    }
    await authClient.organization.setActive({ organizationId: result.data.id });
    setPending(false);
    clearDraft();
    onCreated();
  };

  const cancel = () => {
    clearDraft();
    onCancel?.();
  };

  return (
    <form noValidate onSubmit={submit} className="flex flex-col gap-4">
      <ErrorSummary errors={touched && error ? [{ field: 'workspace-name', message: error }] : []} />
      {serverError ? (
        <p role="alert" className="rounded-control border border-err-border bg-err-bg p-3 text-err">
          {serverError}
        </p>
      ) : null}
      <TextField
        id="workspace-name"
        label="Workspace name"
        autoComplete="organization"
        enterKeyHint="done"
        value={draft.name}
        error={error}
        hint={draft.name ? `Address: ${slugify(draft.name) || '-'}` : 'A new workspace waits for approval before use.'}
        onChange={event => setDraft({ name: event.target.value })}
        onBlur={() => setTouched(true)}
      />
      <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        {onCancel ? (
          <Button variant="ghost" onClick={cancel}>
            Cancel
          </Button>
        ) : null}
        <Button type="submit" variant="primary" pending={pending}>
          Create workspace
        </Button>
      </div>
    </form>
  );
}
