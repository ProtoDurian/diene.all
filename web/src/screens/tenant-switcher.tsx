import { useEffect, useRef, useState } from 'react';
import { Button } from '../components/button.tsx';
import { authClient } from '../lib/auth-client.ts';
import { navigate } from '../lib/router.ts';
import { CreateTenantForm } from './create-tenant.tsx';

type TenantSwitcherProps = {
  open: boolean;
  onClose: () => void;
};

// Selectors open as a modal sheet (bottom on phones), never a dropdown.
export function TenantSwitcher({ open, onClose }: TenantSwitcherProps) {
  const dialog = useRef<HTMLDialogElement>(null);
  const tenants = authClient.useListOrganizations();
  const session = authClient.useSession();
  const [creating, setCreating] = useState(false);
  const [switching, setSwitching] = useState<string | undefined>();
  const activeId = session.data?.session.activeOrganizationId;

  useEffect(() => {
    const element = dialog.current;
    if (!element) return;
    if (open && !element.open) element.showModal();
    if (!open && element.open) element.close();
  }, [open]);

  const choose = async (organizationId: string) => {
    setSwitching(organizationId);
    await authClient.organization.setActive({ organizationId });
    setSwitching(undefined);
    onClose();
  };

  const signOut = async () => {
    await authClient.signOut();
    navigate('/sign-in', true);
  };

  return (
    <dialog
      ref={dialog}
      onClose={onClose}
      aria-labelledby="switcher-title"
      className="mx-0 mt-auto mb-0 w-full max-w-none rounded-t-panel border border-border bg-surface p-0 text-fg shadow-panel backdrop:bg-black/40 sm:m-auto sm:max-w-md sm:rounded-panel"
    >
      <div className="flex flex-col gap-4 p-4 pb-[max(1rem,env(safe-area-inset-bottom))] sm:p-6">
        <div className="flex items-center justify-between gap-2">
          <h2 id="switcher-title" className="font-semibold text-lg">
            {creating ? 'New workspace' : 'Workspaces'}
          </h2>
          <Button variant="ghost" onClick={onClose}>
            Close
          </Button>
        </div>
        {creating ? (
          <CreateTenantForm
            onCreated={() => {
              setCreating(false);
              onClose();
            }}
            onCancel={() => setCreating(false)}
          />
        ) : (
          <>
            <ul className="flex flex-col gap-1">
              {(tenants.data ?? []).map(tenant => (
                <li key={tenant.id}>
                  <button
                    type="button"
                    aria-current={tenant.id === activeId ? 'true' : undefined}
                    disabled={switching !== undefined}
                    onClick={() => choose(tenant.id)}
                    className="flex min-h-11 w-full items-center justify-between rounded-control px-3 text-start hover:bg-surface-2 aria-[current=true]:bg-accent-soft aria-[current=true]:text-accent-strong"
                  >
                    <span className="truncate">{tenant.name}</span>
                    <span className="text-muted text-sm">{tenant.id === activeId ? 'Current' : tenant.slug}</span>
                  </button>
                </li>
              ))}
            </ul>
            <div className="flex flex-col gap-2 border-border border-t pt-4 sm:flex-row sm:justify-between">
              <Button variant="ghost" onClick={signOut}>
                Sign out
              </Button>
              <Button onClick={() => setCreating(true)}>New workspace</Button>
            </div>
          </>
        )}
      </div>
    </dialog>
  );
}
