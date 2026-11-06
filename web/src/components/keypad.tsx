const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'blank', '0', 'del'] as const;

type KeypadProps = {
  value: string;
  maxLength: number;
  onChange: (value: string) => void;
};

// Digits come from this inline keypad on touch screens so the OS keyboard never covers the form.
export function Keypad({ value, maxLength, onChange }: KeypadProps) {
  return (
    <div className="grid grid-cols-3 gap-2 sm:hidden">
      {KEYS.map(key =>
        key === 'blank' ? (
          <span key={key} />
        ) : (
          <button
            key={key}
            type="button"
            aria-label={key === 'del' ? 'Delete digit' : key}
            className="min-h-12 rounded-control border border-border bg-surface-2 font-medium text-lg active:bg-surface-3"
            onClick={() => onChange(key === 'del' ? value.slice(0, -1) : (value + key).slice(0, maxLength))}
          >
            {key === 'del' ? 'Delete' : key}
          </button>
        ),
      )}
    </div>
  );
}
