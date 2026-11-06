import { fileURLToPath } from 'node:url';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

const root = fileURLToPath(new URL('.', import.meta.url));

export default defineConfig({
  root,
  publicDir: 'public',
  build: {
    outDir: fileURLToPath(new URL('../dist/web', import.meta.url)),
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/api': 'http://localhost:8787',
      '/mcp': 'http://localhost:8787',
    },
  },
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'script',
      includeAssets: ['favicon.svg', 'apple-touch-icon.png'],
      manifest: {
        id: '/',
        name: 'Aseity',
        short_name: 'Aseity',
        description: 'A standalone multi-tenant app.',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        theme_color: '#4f52d6',
        background_color: '#fbfbfc',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        navigateFallback: '/index.html',
        // The Worker owns these paths; the service worker must never answer them from cache.
        navigateFallbackDenylist: [/^\/api\//, /^\/mcp/],
        globPatterns: ['**/*.{js,css,html,svg,png,webmanifest}'],
      },
    }),
  ],
});
