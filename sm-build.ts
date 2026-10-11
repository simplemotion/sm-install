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
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
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

// 2b. Pages per channel and per product, from the sm-channel/ template:
//     /<channel>/ lists every product with its install commands, and
//     /<channel>/<product>/ is the page for one product on one channel.
//     The template is not served.
const CHANNELS = [
  { id: 'release', title: 'Release', summary: 'Stable production builds. Open to everyone.' },
  { id: 'preview', title: 'Preview', summary: 'The next release, before it is final. Open to everyone.' },
  { id: 'testing', title: 'Testing', summary: 'In-flight test builds. SimpleMotion staff only.' },
  { id: 'develop', title: 'Develop', summary: 'The earliest development builds. SimpleMotion staff only.' },
];
const STAFF_CHANNELS = new Set(['testing', 'develop']);
// The products that the installer site installs. The base is the internal
// copy; step 3 changes it to /external in the external copy.
const BASE = `https://${DOMAIN}/internal`;
const PRODUCTS = [
  {
    id: 'sm-welcome',
    summary: 'Onboarding. Sets up a SimpleMotion workstation step by step.',
    unix: (ch: string) => `bash -c "$(curl -fsSL ${BASE}/sm-welcome.sh)" sm-welcome --channel ${ch}`,
    windows: (ch: string) => `$env:SM_CHANNEL='${ch}'; irm ${BASE}/sm-welcome.ps1 | iex`,
  },
  {
    id: 'sm-simplicity',
    summary: 'Simplicity. Installs the sm-simplicity application.',
    unix: (ch: string) => `SM_CHANNEL=${ch} bash -c "$(curl -fsSL ${BASE}/sm-simplicity.sh)" sm-simplicity`,
    windows: (ch: string) => `$env:SM_CHANNEL='${ch}'; irm ${BASE}/sm-simplicity.ps1 | iex`,
  },
];
const COMMANDS = /<!--SM_COMMANDS_BEGIN-->[\s\S]*<!--SM_COMMANDS_END-->/;
const commandsHtml = (p: (typeof PRODUCTS)[number], ch: string): string =>
  `  <p class="os">macOS / Linux</p>\n  <pre><code>${p.unix(ch)}</code></pre>\n` +
  `  <p class="os">Windows (PowerShell)</p>\n  <pre><code>${p.windows(ch)}</code></pre>\n`;
const navHtml = (current: string, href: (c: string) => string): string =>
  CHANNELS.map(
    (c) => `<a href="${href(c.id)}"${c.id === current ? ' class="active" aria-current="page"' : ''}>${c.title}</a>`,
  ).join('');
{
  // The SimpleMotion banner, copied from the welcome page so that the site
  // holds one copy of the image.
  const banner = readFileSync(`${TREE}/sm-welcome/index.html`, 'utf8').match(/<img class="banner"[^>]*>/)?.[0];
  if (!banner) throw new Error('sm-welcome/index.html has no <img class="banner">');
  const raw = readFileSync(`${TREE}/sm-channel/index.html`, 'utf8');
  if (!raw.includes('<!--SM_BANNER-->')) throw new Error('sm-channel/index.html has no SM_BANNER marker');
  const tmpl = raw.replace('<!--SM_BANNER-->', banner);
  if (!COMMANDS.test(tmpl)) throw new Error('sm-channel/index.html has no SM_COMMANDS markers');
  const fill = (v: Record<string, string>): string => {
    let html = tmpl;
    for (const [k, val] of Object.entries(v)) html = html.split(`{{${k}}}`).join(val);
    if (html.includes('{{')) throw new Error(`page "${v.PAGE_TITLE}" has an unfilled placeholder`);
    return html;
  };
  let pages = 0;
  for (const ch of CHANNELS) {
    const body = PRODUCTS.map(
      (p) => `  <h2><a href="${p.id}/">${p.id}</a></h2>\n  <p class="about">${p.summary}</p>\n` + commandsHtml(p, ch.id),
    ).join('\n');
    mkdirSync(`${TREE}/${ch.id}`, { recursive: true });
    writeFileSync(
      `${TREE}/${ch.id}/index.html`,
      fill({
        PAGE_TITLE: `${ch.title} channel`,
        CRUMB: '',
        HEADING: `<span class="ch">${ch.title}</span> channel`,
        SUMMARY: ch.summary,
        NAV: navHtml(ch.id, (c) => `../${c}/`),
        BODY: body,
      }),
    );
    pages++;
    for (const p of PRODUCTS) {
      mkdirSync(`${TREE}/${ch.id}/${p.id}`, { recursive: true });
      writeFileSync(
        `${TREE}/${ch.id}/${p.id}/index.html`,
        fill({
          PAGE_TITLE: `${p.id} on the ${ch.title} channel`,
          CRUMB: `<p class="crumb"><a href="../">&larr; All products on the ${ch.title} channel</a></p>`,
          HEADING: `<span class="ch">${p.id}</span>`,
          SUMMARY: `${p.summary} ${ch.title} channel: ${ch.summary}`,
          NAV: navHtml(ch.id, (c) => `../../${c}/${p.id}/`),
          BODY: commandsHtml(p, ch.id),
        }),
      );
      pages++;
    }
  }
  rmSync(`${TREE}/sm-channel`, { recursive: true, force: true });
  console.log(`built ${pages} channel and product pages`);
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

// The external installer refuses the staff channels, so the external pages
// for them show a notice instead of commands. The notice names no URL: the
// rewrite above would change an /internal URL to /external.
const STAFF_NOTICE = `<div class="notice">This channel is for SimpleMotion staff (the executive and
  employees cohorts) only. Staff use the internal copy of the installer site. The
  <a href="https://github.com/simplemotion/sm-install#readme">sm-install README</a> gives its address.</div>`;
for (const ch of STAFF_CHANNELS) {
  for (const page of [`${ext}/${ch}/index.html`, ...PRODUCTS.map((p) => `${ext}/${ch}/${p.id}/index.html`)]) {
    const html = readFileSync(page, 'utf8');
    writeFileSync(page, html.replace(COMMANDS, STAFF_NOTICE));
  }
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
// Every channel, and every product on every channel, has a page in BOTH
// copies, always: /internal/<channel>/[<product>/] and /external/... are
// permanent URLs. A missing page fails the build.
for (const ch of CHANNELS) {
  for (const aud of ['internal', 'external']) {
    for (const sub of ['', ...PRODUCTS.map((p) => `${p.id}/`)]) {
      const page = `${SITE}/${aud}/${ch.id}/${sub}index.html`;
      const where = `${aud}/${ch.id}/${sub}`;
      if (!existsSync(page)) throw new Error(`${where} is missing: every page must exist in both copies`);
      const html = readFileSync(page, 'utf8');
      if (!html.includes('<img class="banner"')) throw new Error(`${where} has no SimpleMotion banner`);
      const staffOnly = aud === 'external' && STAFF_CHANNELS.has(ch.id);
      const hasCommands = html.includes('<pre><code>');
      if (staffOnly === hasCommands) {
        throw new Error(`${where}: ${staffOnly ? 'shows commands for a staff channel' : 'has no install commands'}`);
      }
    }
  }
}
for (const file of walk(ext).filter((f) => REWRITTEN.test(f))) {
  if (readFileSync(file, 'utf8').includes(internalUrl)) fail(`${file} still has an internal URL`);
}
console.log(`built ${SITE}/internal and ${SITE}/external — ${urls} URLs changed to /external`);
