// Build step for install.simplemotion.com (Pages, Actions deploy).
//
// 1. esbuild bundles + minifies sm-welcome/sm-welcome.ts into an IIFE.
// 2. The served tree is assembled under _site/, with the welcome page's
//    <!--SM_WELCOME_SCRIPT--> placeholder replaced by the inlined bundle.
//    No .js is committed; the browser-served script is build output.
//
// Run with Node >= 24 (strips TS types natively): `node sm-build.ts`.

import { buildSync } from 'esbuild';
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';

const SITE = '_site';

// Repo entries that are build/dev sources, not served content.
const SKIP = new Set([
  '.git',
  '.github',
  'node_modules',
  '_site',
  'package.json',
  'package-lock.json',
  'tsconfig.json',
  'sm-build.ts',
]);

// 1. Bundle the welcome-page script.
const result = buildSync({
  entryPoints: ['sm-welcome/sm-welcome.ts'],
  bundle: true,
  minify: true,
  format: 'iife',
  target: 'es2020',
  write: false,
});
const js = result.outputFiles[0].text.trimEnd();

// 2. Assemble the served tree.
rmSync(SITE, { recursive: true, force: true });
mkdirSync(SITE, { recursive: true });
for (const entry of readdirSync('.')) {
  if (SKIP.has(entry)) continue;
  cpSync(entry, `${SITE}/${entry}`, { recursive: true });
}
// The .ts source is not served.
rmSync(`${SITE}/sm-welcome/sm-welcome.ts`, { force: true });

// 3. Inline the bundle into the welcome page.
const page = `${SITE}/sm-welcome/index.html`;
const tmpl = readFileSync(page, 'utf8');
const PLACEHOLDER = '<!--SM_WELCOME_SCRIPT-->';
if (!tmpl.includes(PLACEHOLDER)) {
  throw new Error(`placeholder ${PLACEHOLDER} not found in ${page}`);
}
writeFileSync(page, tmpl.replace(PLACEHOLDER, `<script>${js}</script>`));

console.log(`built ${SITE}/ — inlined ${js.length} bytes of minified JS into sm-welcome/index.html`);
