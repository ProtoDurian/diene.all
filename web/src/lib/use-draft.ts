import { useCallback, useState } from 'react';

const PREFIX = 'aseity:draft:';

function read<T>(key: string, initial: T): T {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    return raw === null ? initial : { ...initial, ...(JSON.parse(raw) as Partial<T>) };
  } catch {
    return initial;
  }
}

export function useDraft<T extends object>(key: string, initial: T) {
  const [value, setValue] = useState<T>(() => read(key, initial));

  const update = useCallback(
    (patch: Partial<T>) => {
      setValue(previous => {
        const next = { ...previous, ...patch };
        try {
          localStorage.setItem(PREFIX + key, JSON.stringify(next));
        } catch {}
        return next;
      });
    },
    [key],
  );

  const clear = useCallback(() => {
    try {
      localStorage.removeItem(PREFIX + key);
    } catch {}
    setValue(initial);
  }, [key, initial]);

  return [value, update, clear] as const;
}
