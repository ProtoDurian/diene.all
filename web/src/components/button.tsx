import type { ButtonHTMLAttributes } from 'react';
import { Spinner } from './spinner.tsx';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';

const VARIANTS: Record<Variant, string> = {
  primary: 'bg-accent text-accent-fg hover:bg-accent-strong border-transparent',
  secondary: 'bg-surface text-fg border-border-strong hover:bg-surface-2',
  ghost: 'bg-transparent text-fg-soft border-transparent hover:bg-surface-2',
  danger: 'bg-surface text-err border-err-border hover:bg-err-bg',
};

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  pending?: boolean;
};

export function Button({ variant = 'secondary', pending = false, className = '', children, disabled, ...rest }: ButtonProps) {
  return (
    <button
      type="button"
      {...rest}
      disabled={disabled || pending}
      aria-busy={pending || undefined}
      className={`inline-flex min-h-11 items-center justify-center gap-2 rounded-control border px-4 font-medium shadow-control transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-60 ${VARIANTS[variant]} ${className}`}
    >
      {pending ? <Spinner /> : null}
      {children}
    </button>
  );
}
