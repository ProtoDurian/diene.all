import type { InputHTMLAttributes, TextareaHTMLAttributes } from 'react';

type FieldShell = {
  id: string;
  label: string;
  error?: string | undefined;
  hint?: string;
};

const CONTROL =
  'w-full rounded-control border bg-surface px-3 text-fg placeholder:text-muted focus-visible:outline-2 focus-visible:outline-offset-0';

function describedBy(id: string, error?: string, hint?: string): string | undefined {
  const ids = [error ? `${id}-error` : '', hint ? `${id}-hint` : ''].filter(Boolean);
  return ids.length > 0 ? ids.join(' ') : undefined;
}

function Messages({ id, error, hint }: Omit<FieldShell, 'label'>) {
  return (
    <>
      {hint ? (
        <p id={`${id}-hint`} className="text-sm text-muted">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={`${id}-error`} className="text-sm text-err">
          {error}
        </p>
      ) : null}
    </>
  );
}

export function TextField({ id, label, error, hint, ...rest }: FieldShell & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="font-medium text-fg-soft text-sm">
        {label}
      </label>
      <input
        id={id}
        name={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy(id, error, hint)}
        className={`${CONTROL} min-h-11 ${error ? 'border-err' : 'border-border-strong'}`}
        {...rest}
      />
      <Messages id={id} error={error} hint={hint} />
    </div>
  );
}

export function TextAreaField({ id, label, error, hint, ...rest }: FieldShell & TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="font-medium text-fg-soft text-sm">
        {label}
      </label>
      <textarea
        id={id}
        name={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy(id, error, hint)}
        className={`${CONTROL} min-h-28 py-2 ${error ? 'border-err' : 'border-border-strong'}`}
        {...rest}
      />
      <Messages id={id} error={error} hint={hint} />
    </div>
  );
}
