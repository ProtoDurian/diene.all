export function Logo({ className = 'size-8' }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" className={className} role="img" aria-label="Aseity">
      <rect width="100" height="100" rx="22" className="fill-accent" />
      <circle cx="50" cy="50" r="22.4" fill="none" strokeWidth="9.6" className="stroke-accent-fg" />
      <circle cx="50" cy="50" r="7.2" className="fill-accent-fg" />
    </svg>
  );
}
