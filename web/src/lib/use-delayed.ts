import { useEffect, useState } from 'react';

export function useDelayed(active: boolean, delayMs = 100): boolean {
  const [shown, setShown] = useState(false);
  useEffect(() => {
    if (!active) {
      setShown(false);
      return;
    }
    const timer = setTimeout(() => setShown(true), delayMs);
    return () => clearTimeout(timer);
  }, [active, delayMs]);
  return shown;
}
