import { useEffect, useState } from 'react';
import { Button } from '../components/button.tsx';
import { Logo } from '../components/logo.tsx';
import { authClient, followRedirect } from '../lib/auth-client.ts';

const SCOPE_LABELS: Record<string, string> = {
  openid: 'Confirm who you are',
  profile: 'See your name and picture',
  email: 'See your email address',
  offline_access: 'Stay signed in when you are away',
};

export function ConsentScreen() {
  const params = new URLSearchParams(window.location.search);
  const clientId = params.get('client_id') ?? '';
  const scopes = (params.get('scope') ?? '').split(' ').filter(scope => scope.length > 0);
  const [clientName, setClientName] = useState<string | undefined>();
  const [pending, setPending] = useState<'accept' | 'deny' | undefined>();
  const [error, setError] = useState<string | undefined>();

  useEffect(() => {
    if (!clientId) return;
    void authClient.oauth2.publicClient({ query: { client_id: clientId } }).then(result => {
      if (result.data?.client_name) setClientName(result.data.client_name);
    });
  }, [clientId]);

  const decide = async (accept: boolean) => {
    setPending(accept ? 'accept' : 'deny');
    setError(undefined);
    const result = await authClient.oauth2.consent({ accept });
    if (result.error || !followRedirect(result.data)) {
      setPending(undefined);
      setError(result.error?.message ?? 'We could not finish this request. Start the sign-in again from the app.');
    }
  };

  const app = clientName ?? 'An application';

  return (
    <main className="flex min-h-dvh items-start justify-center sm:items-center sm:p-8">
      <section className="flex w-full flex-col gap-6 px-4 pt-[max(2rem,env(safe-area-inset-top))] pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:max-w-md sm:rounded-panel sm:border sm:border-border sm:bg-surface sm:p-8 sm:shadow-panel">
        <header className="flex flex-col items-start gap-3">
          <Logo className="size-10" />
          <h1 className="font-semibold text-2xl tracking-tight">Allow access?</h1>
          <p className="text-fg-soft">
            <strong className="text-fg">{app}</strong> wants to use your account.
          </p>
        </header>
        {scopes.length > 0 ? (
          <ul className="flex flex-col gap-2 rounded-control border border-border bg-surface-2 p-3">
            {scopes.map(scope => (
              <li key={scope}>{SCOPE_LABELS[scope] ?? scope}</li>
            ))}
          </ul>
        ) : null}
        {error ? (
          <p role="alert" className="rounded-control border border-err-border bg-err-bg p-3 text-err">
            {error}
          </p>
        ) : null}
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button
            variant="ghost"
            pending={pending === 'deny'}
            disabled={pending === 'accept'}
            onClick={() => decide(false)}
          >
            Deny
          </Button>
          <Button
            variant="primary"
            pending={pending === 'accept'}
            disabled={pending === 'deny'}
            onClick={() => decide(true)}
          >
            Allow
          </Button>
        </div>
      </section>
    </main>
  );
}
