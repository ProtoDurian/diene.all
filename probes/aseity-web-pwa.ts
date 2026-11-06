import { expectBunGreen } from './lib/bun-command.ts';

type ProbeRepo = {
  exec(command: string, options?: { timeoutMs?: number }): Promise<{ exitCode: number; stdout: string; stderr: string }>;
  read(path: string): Promise<string>;
  write(path: string, content: string): Promise<void>;
  glob(pattern: string): Promise<string[]>;
};

type ManifestIcon = { src?: unknown; sizes?: unknown; type?: unknown };

const OUT = 'dist/web';
const build =
  "nix develop .#ci -c bash -lc 'bun install --frozen-lockfile && rm -rf dist/web && ./node_modules/.bin/vite build --config web/vite.config.ts'";

async function exists(repo: ProbeRepo, path: string): Promise<boolean> {
  return (await repo.glob(path)).length === 1;
}

async function manifestFailures(repo: ProbeRepo): Promise<string[]> {
  if (!(await exists(repo, `${OUT}/manifest.webmanifest`))) return ['manifest.webmanifest is missing'];
  let manifest: { name?: unknown; start_url?: unknown; display?: unknown; icons?: unknown };
  try {
    manifest = JSON.parse(await repo.read(`${OUT}/manifest.webmanifest`));
  } catch {
    return ['manifest.webmanifest is not valid JSON'];
  }
  const failures: string[] = [];
  if (typeof manifest.name !== 'string' || manifest.name === '') failures.push('manifest has no name');
  if (typeof manifest.start_url !== 'string') failures.push('manifest has no start_url');
  if (!['standalone', 'fullscreen', 'minimal-ui'].includes(String(manifest.display))) {
    failures.push('manifest display is not installable');
  }
  const icons: ManifestIcon[] = Array.isArray(manifest.icons) ? manifest.icons : [];
  for (const size of ['192x192', '512x512']) {
    const icon = icons.find(candidate => candidate.sizes === size && candidate.type === 'image/png');
    if (!icon || typeof icon.src !== 'string') {
      failures.push(`manifest has no ${size} PNG icon`);
    } else if (!(await exists(repo, `${OUT}/${icon.src.replace(/^\//, '')}`))) {
      failures.push(`icon ${icon.src} is not in the build`);
    }
  }
  return failures;
}

async function pwaFailures(repo: ProbeRepo): Promise<string[]> {
  const failures = await manifestFailures(repo);
  if (!(await exists(repo, `${OUT}/index.html`))) return [...failures, 'index.html is missing'];
  const html = await repo.read(`${OUT}/index.html`);
  if (!/<link[^>]+rel="manifest"[^>]+href="\/manifest\.webmanifest"/.test(html)) {
    failures.push('index.html does not link the manifest');
  }
  if (!(await exists(repo, `${OUT}/sw.js`))) failures.push('sw.js is missing');
  const register = (await exists(repo, `${OUT}/registerSW.js`)) ? await repo.read(`${OUT}/registerSW.js`) : html;
  if (!register.includes('serviceWorker') || !register.includes('sw.js')) {
    failures.push('the app never registers sw.js');
  }
  return failures;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-aseity-web-pwa-green',
      description: 'The web build emits an installable PWA: manifest, service worker, icons, and a linked manifest.',
      kind: 'baseline',
      async run(repo: ProbeRepo) {
        await expectBunGreen(repo, build, 'aseity-web-pwa');
        const failures = await pwaFailures(repo);
        if (failures.length > 0) throw new Error(`web build is not an installable PWA: ${failures.join('; ')}`);
      },
    },
    {
      name: 'mutation-aseity-web-pwa-caught',
      description: 'Dropping the PWA plugin from the web build leaves no manifest or service worker, which the check catches.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: ProbeRepo) {
        const config = (await repo.glob('web/vite.config.*')).sort()[0];
        if (!config) throw new Error('web/vite.config is missing');
        const source = await repo.read(config);
        if (!/\bVitePWA\(/.test(source)) throw new Error(`${config} does not call VitePWA`);
        await repo.write(config, source.replace(/\bVitePWA\(/, '((_pwa: unknown) => undefined)('));
        await expectBunGreen(repo, build, 'aseity-web-pwa');
        const failures = await pwaFailures(repo);
        if (!failures.includes('manifest.webmanifest is missing') || !failures.includes('sw.js is missing')) {
          throw new Error(`the PWA check stayed green without the PWA plugin: ${failures.join('; ') || 'no failures'}`);
        }
      },
    },
  ],
};
