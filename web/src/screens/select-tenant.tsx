import { useState } from 'react';
import { Button } from '../components/button.tsx';
import { Logo } from '../components/logo.tsx';
import { authClient, followRedirect } from '../lib/auth-client.ts';
import { CreateTenantForm } from './create-tenant.tsx';

export function SelectTenantScreen() {
  const tenants = authClient.useListOrganizations();
  const [creating, setCreating] = useState(false);
  const [pending, setPending] = useState<string | undefined>();
  const [error, setError] = useState<string | undefined>();
  const list = tenants.data ?? [];

  const proceed = async () => {
    const result = await authClient.oauth2.continue({ postLogin: true });
    if (result.error || !followRedirect(result.data)) {
      setPending(undefined);
      setError(result.error?.message ?? 'We could not finish this request. Start the sign-in again from the app.');
    }
  };

  const choose = async (organizationId: string) => {
    setPending(organizationId);
    setError(undefined);
    const active = await authClient.organization.setActive({ organizationId });
    if (active.error) {
      setPending(undefined);
      setError(active.error.message ?? 'We could not open that workspace. Try again.');
      return;
    }
    await proceed();
  };

  return (
    <main className="flex min-h-dvh items-start justify-center sm:items-center sm:p-8">
      <section className="flex w-full flex-col gap-6 px-4 pt-[max(2rem,env(safe-area-inset-top))] pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:max-w-md sm:rounded-panel sm:border sm:border-border sm:bg-surface sm:p-8 sm:shadow-panel">
        <header className="flex flex-col items-start gap-3">
          <Logo className="size-10" />
          <h1 className="font-semibold text-2xl tracking-tight">{creating ? 'New workspace' : 'Choose a workspace'}</h1>
          <p className="text-fg-soft">The app you are signing in to will only see this workspace.</p>
        </header>
        {error ? (
          <p role="alert" className="rounded-control border border-err-border bg-err-bg p-3 text-err">
            {error}
          </p>
        ) : null}
        {creating ? (
          <CreateTenantForm
            onCreated={() => {
              setPending('new');
              void proceed();
            }}
            onCancel={() => setCreating(false)}
          />
        ) : (
          <>
            {tenants.isPending ? <div className="h-24 animate-pulse rounded-control bg-surface-2" /> : null}
            {!tenants.isPending && list.length === 0 ? (
              <p className="rounded-panel border border-border border-dashed p-4 text-fg-soft">
                You have no workspace yet. Create one to continue.
              </p>
            ) : null}
            <ul className="flex flex-col gap-1">
              {list.map(tenant => (
                <li key={tenant.id}>
                  <Button
                    variant="secondary"
                    className="w-full justify-between"
                    pending={pending === tenant.id}
                    disabled={pending !== undefined}
                    onClick={() => choose(tenant.id)}
                  >
                    <span className="truncate">{tenant.name}</span>
                    <span className="text-muted text-sm">{tenant.slug}</span>
                  </Button>
                </li>
              ))}
            </ul>
            <div className="flex flex-col sm:flex-row sm:justify-end">
              <Button variant="ghost" disabled={pending !== undefined} onClick={() => setCreating(true)}>
                New workspace
              </Button>
            </div>
          </>
        )}
      </section>
    </main>
  );
}
