import { useEffect, useState } from 'react';
import { Button } from './components/button.tsx';
import { Logo } from './components/logo.tsx';
import { OfflineBanner } from './components/offline-banner.tsx';
import { authClient } from './lib/auth-client.ts';
import { navigate, usePath } from './lib/router.ts';
import { useDelayed } from './lib/use-delayed.ts';
import { ConsentScreen } from './screens/consent.tsx';
import { CreateTenantForm } from './screens/create-tenant.tsx';
import { NotesScreen } from './screens/notes.tsx';
import { SelectTenantScreen } from './screens/select-tenant.tsx';
import { SignInScreen } from './screens/sign-in.tsx';
import { TenantSwitcher } from './screens/tenant-switcher.tsx';

function BrandLoader() {
  const shown = useDelayed(true);
  return (
    <div role="status" aria-label="Loading" className="flex min-h-dvh items-center justify-center">
      {shown ? <Logo className="size-12 animate-pulse" /> : null}
    </div>
  );
}

function Workspace({ email }: { email: string }) {
  const tenants = authClient.useListOrganizations();
  const active = authClient.useActiveOrganization();
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const loading = tenants.isPending || active.isPending;
  const openSwitcher = () => setSwitcherOpen(true);

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="sticky top-0 z-10 border-border border-b bg-surface/90 pt-[env(safe-area-inset-top)] backdrop-blur">
        <div className="mx-auto flex h-14 max-w-5xl items-center justify-between gap-3 px-4 sm:px-6">
          <div className="flex min-w-0 items-center gap-2">
            <Logo className="size-7 shrink-0" />
            <span className="hidden font-semibold sm:inline">Aseity</span>
          </div>
          <Button variant="ghost" className="min-w-0 max-w-[60%]" onClick={openSwitcher} aria-haspopup="dialog">
            <span className="truncate">{active.data?.name ?? 'Choose workspace'}</span>
            <span className="hidden truncate text-muted text-sm md:inline">{email}</span>
          </Button>
        </div>
      </header>
      <OfflineBanner />
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6 pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:px-6">
        {loading ? <div className="h-64 animate-pulse rounded-panel bg-surface-2" /> : null}
        {!loading && active.data ? (
          <NotesScreen key={active.data.id} tenantName={active.data.name} onSwitch={openSwitcher} />
        ) : null}
        {!loading && !active.data && (tenants.data ?? []).length === 0 ? (
          <section className="mx-auto flex max-w-md flex-col gap-4">
            <h1 className="font-semibold text-xl">Create your workspace</h1>
            <p className="text-fg-soft">A workspace holds your team's data. Everything you add stays inside it.</p>
            <CreateTenantForm onCreated={() => undefined} />
          </section>
        ) : null}
        {!loading && !active.data && (tenants.data ?? []).length > 0 ? (
          <section className="mx-auto flex max-w-md flex-col items-start gap-4">
            <h1 className="font-semibold text-xl">Choose a workspace</h1>
            <p className="text-fg-soft">You belong to more than one. Pick the one to open.</p>
            <Button variant="primary" onClick={openSwitcher}>
              Choose workspace
            </Button>
          </section>
        ) : null}
      </main>
      <TenantSwitcher open={switcherOpen} onClose={() => setSwitcherOpen(false)} />
    </div>
  );
}

function Home() {
  const session = authClient.useSession();
  const signedOut = !session.isPending && !session.data;

  useEffect(() => {
    if (signedOut) navigate('/sign-in', true);
  }, [signedOut]);

  if (!session.data) return <BrandLoader />;
  return <Workspace email={session.data.user.email} />;
}

export function App() {
  const path = usePath();
  if (path === '/sign-in') return <SignInScreen />;
  if (path === '/consent') return <ConsentScreen />;
  if (path === '/select-tenant') return <SelectTenantScreen />;
  return <Home />;
}
