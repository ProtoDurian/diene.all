import { useEffect, useRef } from 'react';

type ErrorSummaryProps = {
  errors: ReadonlyArray<{ field: string; message: string }>;
};

export function ErrorSummary({ errors }: ErrorSummaryProps) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (errors.length > 0) ref.current?.focus();
  }, [errors]);
  if (errors.length === 0) return null;
  return (
    <div ref={ref} tabIndex={-1} role="alert" className="rounded-control border border-err-border bg-err-bg p-3 text-err">
      <p className="font-medium">Fix {errors.length === 1 ? 'this' : 'these'} to continue:</p>
      <ul className="mt-1 list-disc ps-5">
        {errors.map(error => (
          <li key={error.field}>
            <a className="underline" href={`#${error.field}`}>
              {error.message}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}
