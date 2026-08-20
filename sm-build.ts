// Build step for install.simplemotion.com (Pages, Actions deploy).
//
// 1. esbuild bundles + minifies each page's .ts entry into an IIFE.
// 2. The served tree is assembled under _site/, with each page's
//    <!--SM_*_SCRIPT--> placeholder replaced by its inlined bundle.
//    No .js is committed; the browser-served script is build output.
//
// Run with Node >= 24 (strips TS types natively): `node sm-build.ts`.

import { buildSync } from 'esbuild';
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';

const SITE = '_site';

// The interactive pages: each has a dir with index.html (carrying the
// placeholder) and a same-named .ts entry that gets bundled + inlined.
const PAGES = [
  { dir: 'sm-welcome', entry: 'sm-welcome.ts', placeholder: '<!--SM_WELCOME_SCRIPT-->' },
  { dir: 'sm-simplicity', entry: 'sm-simplicity.ts', placeholder: '<!--SM_SIMPLICITY_SCRIPT-->' },
];

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
  // Renderer tests and the transcript preview. Dev sources — they exercise
  // sm-install-lib.sh, they are not served from it.
  'tests',
]);

// 1. Assemble the served tree.
rmSync(SITE, { recursive: true, force: true });
mkdirSync(SITE, { recursive: true });
for (const entry of readdirSync('.')) {
  if (SKIP.has(entry)) continue;
  cpSync(entry, `${SITE}/${entry}`, { recursive: true });
}

// 2. Bundle each page's script and inline it; the .ts source is not served.
for (const { dir, entry, placeholder } of PAGES) {
  const result = buildSync({
    entryPoints: [`${dir}/${entry}`],
    bundle: true,
    minify: true,
    format: 'iife',
    target: 'es2020',
    write: false,
  });
  const js = result.outputFiles[0].text.trimEnd();

  rmSync(`${SITE}/${dir}/${entry}`, { force: true });

  const page = `${SITE}/${dir}/index.html`;
  const tmpl = readFileSync(page, 'utf8');
  if (!tmpl.includes(placeholder)) {
    throw new Error(`placeholder ${placeholder} not found in ${page}`);
  }
  writeFileSync(page, tmpl.replace(placeholder, `<script>${js}</script>`));

  console.log(`built ${SITE}/${dir}/index.html — inlined ${js.length} bytes of minified JS`);
}
