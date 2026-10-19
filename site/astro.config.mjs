import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Public URL of the site, used for canonical links, Open Graph and the sitemap.
// Set it at build time: SITE_URL=https://your-domain npm run build
const site = process.env.SITE_URL || 'https://example.com';

export default defineConfig({
  site,
  output: 'static',
  trailingSlash: 'ignore',
  build: { format: 'directory', inlineStylesheets: 'auto' },
  integrations: [sitemap()],
});
