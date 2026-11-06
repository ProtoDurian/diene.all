import { useState } from 'react';
import type { Problem } from '../lib/problem.ts';
import { Button } from './button.tsx';

export function FailureScreen({ problem }: { problem: Problem }) {
  const [copied, setCopied] = useState(false);
  const report = JSON.stringify(problem, null, 2);
  const copy = async () => {
    await navigator.clipboard.writeText(report);
    setCopied(true);
  };
  return (
    <section className="mx-auto flex max-w-xl flex-col gap-4 p-4 sm:p-8">
      <h1 className="font-semibold text-xl">Something went wrong</h1>
      <p className="text-fg-soft">
        {problem.detail ?? 'The app hit an error it cannot recover from. Reload to try again, or send the details below to support.'}
      </p>
      <pre className="overflow-x-auto rounded-control border border-border bg-surface-2 p-3 font-mono text-sm">{report}</pre>
      <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
        <Button onClick={copy}>{copied ? 'Copied' : 'Copy error details'}</Button>
        <Button variant="primary" onClick={() => window.location.reload()}>
          Reload
        </Button>
      </div>
    </section>
  );
}
