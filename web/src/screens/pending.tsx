import { Button } from '../components/button.tsx';

export function PendingScreen({
  tenantName,
  onRetry,
  onSwitch,
}: {
  tenantName: string;
  onRetry: () => void;
  onSwitch: () => void;
}) {
  return (
    <section className="flex flex-col items-start gap-4 rounded-panel border border-warn-border bg-warn-bg p-4 sm:p-6">
      <h1 className="font-semibold text-warn text-xl">Waiting for approval</h1>
      <p className="text-fg-soft">
        <strong className="text-fg">{tenantName}</strong> is new and needs an administrator to approve it. You can use
        it as soon as it is approved. Nothing is lost while you wait.
      </p>
      <div className="flex w-full flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <Button variant="ghost" onClick={onSwitch}>
          Switch workspace
        </Button>
        <Button variant="primary" onClick={onRetry}>
          Check again
        </Button>
      </div>
    </section>
  );
}
