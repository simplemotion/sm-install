// Build step for install.simplemotion.dev (Pages, Actions deploy).
//
// 1. esbuild bundles + minifies each page's .ts entry into an IIFE.
// 2. The served tree is assembled once, with each page's
//    <!--SM_*_SCRIPT--> placeholder replaced by its inlined bundle.
//    No .js is committed; the browser-served script is build output.
// 3. The tree is written twice, as _site/internal/ and _site/external/.
//    The source is the internal copy. In the external copy the build
//    changes each /internal URL to /external and each audience marker
//    to 'external'. The build fails if the count of changes is wrong.
//
// Run with Node >= 24 (strips TS types natively): `node sm-build.ts`.

import { buildSync } from 'esbuild';
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SITE = '_site';
// The assembled tree, before it is written out per audience.
const TREE = `${SITE}/.tree`;
const DOMAIN = 'install.simplemotion.dev';

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
  // Pages takes the custom domain from the repo settings, not this file.
  'CNAME',
  // Renderer tests and the transcript preview. Dev sources — they exercise
  // sm-install-lib.sh, they are not served from it.
  'tests',
]);

// 1. Assemble the served tree.
rmSync(SITE, { recursive: true, force: true });
mkdirSync(SITE, { recursive: true });
mkdirSync(TREE, { recursive: true });
for (const entry of readdirSync('.')) {
  if (SKIP.has(entry)) continue;
  cpSync(entry, `${TREE}/${entry}`, { recursive: true });
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

  rmSync(`${TREE}/${dir}/${entry}`, { force: true });

  const page = `${TREE}/${dir}/index.html`;
  const tmpl = readFileSync(page, 'utf8');
  if (!tmpl.includes(placeholder)) {
    throw new Error(`placeholder ${placeholder} not found in ${page}`);
  }
  writeFileSync(page, tmpl.replace(placeholder, `<script>${js}</script>`));

  console.log(`built ${dir}/index.html — inlined ${js.length} bytes of minified JS`);
}

// 3. Write the tree once per audience.
const walk = (dir: string): string[] =>
  readdirSync(dir).flatMap((e) => {
    const p = join(dir, e);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

// The audience markers. Each script that fetches a sibling carries exactly one.
const MARKERS: [RegExp, string][] = [
  [/^SM_INSTALL_AUDIENCE='internal'$/m, "SM_INSTALL_AUDIENCE='external'"],
  [/^\$SmInstallAudience = 'internal'$/m, "$SmInstallAudience = 'external'"],
];
const MARKED = [
  'sm-install.sh', 'sm-welcome.sh', 'sm-simplicity.sh',
  'sm-install.ps1', 'sm-welcome.ps1', 'sm-simplicity.ps1',
];
const PAGE_DIRS = PAGES.map((p) => p.dir);

cpSync(TREE, `${SITE}/internal`, { recursive: true });
cpSync(TREE, `${SITE}/external`, { recursive: true });
rmSync(TREE, { recursive: true, force: true });

const ext = `${SITE}/external`;
// Scripts and pages only. The served docs describe both copies, so they stay as written.
const REWRITTEN = /\.(sh|ps1|html)$/;
const internalUrl = `${DOMAIN}/internal`;
const externalUrl = `${DOMAIN}/external`;
let urls = 0;
for (const file of walk(ext)) {
  if (!REWRITTEN.test(file)) continue;
  let text = readFileSync(file, 'utf8');
  urls += text.split(internalUrl).length - 1;
  text = text.split(internalUrl).join(externalUrl);
  for (const [re, to] of MARKERS) text = text.replace(re, to);
  writeFileSync(file, text);
}

// Verify the effect, not the steps.
const fail = (msg: string): never => {
  throw new Error(`external copy: ${msg}`);
};
for (const name of MARKED) {
  const text = readFileSync(`${ext}/${name}`, 'utf8');
  if (MARKERS.some(([re]) => re.test(text))) fail(`${name} still has the internal marker`);
  if (!text.includes("'external'")) fail(`${name} has no external marker`);
}
for (const dir of PAGE_DIRS) {
  const html = readFileSync(`${ext}/${dir}/index.html`, 'utf8');
  if (!html.includes(externalUrl)) fail(`${dir}/index.html has no external base`);
}
for (const file of walk(ext).filter((f) => REWRITTEN.test(f))) {
  if (readFileSync(file, 'utf8').includes(internalUrl)) fail(`${file} still has an internal URL`);
}
console.log(`built ${SITE}/internal and ${SITE}/external — ${urls} URLs changed to /external`);
