// Build step for the two installer sites (Azure Static Web Apps):
// install.simplemotion.dev (internal) and install.simplemotion.com (external).
//
// 1. esbuild bundles + minifies each page's .ts entry into an IIFE.
// 2. The served tree is assembled once, with each page's
//    <!--SM_*_SCRIPT--> placeholder replaced by its inlined bundle.
//    No .js is committed; the browser-served script is build output.
// 3. The build writes the tree twice, as _site/int/ and _site/ext/. Each is
//    the root of its own domain. The source is the internal copy. In the
//    external copy the build changes each internal domain to the external
//    domain and each audience marker to 'external'. The build fails if a
//    change is missing.
//
// Run with Node >= 24 (strips TS types natively): `node sm-build.ts`.

import { buildSync } from 'esbuild';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SITE = '_site';
// The assembled tree, before it is written out per audience.
const TREE = `${SITE}/.tree`;
// The internal copy: executive and employees, every channel. Served by the
// SWA sm-portal-install-int.
const INT_DOMAIN = 'install.simplemotion.dev';
// The external copy: freelance and customers, release and preview only.
// Served by the SWA sm-portal-install-ext.
const EXT_DOMAIN = 'install.simplemotion.com';
// The checks below match the whole origin, not the bare host.
const INT_ORIGIN = `https://${INT_DOMAIN}`;
const EXT_ORIGIN = `https://${EXT_DOMAIN}`;

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
// copy; step 3 changes it to the external domain in the external copy.
const BASE = INT_ORIGIN;
const PRODUCTS = [
  {
    id: 'sm-welcome',
    summary: 'Onboarding. Sets up a SimpleMotion workstation step by step.',
    unix: (ch: string) => `bash -c "$(curl -fsSL ${BASE}/sm-welcome.sh)" sm-welcome --channel ${ch}`,
    windows: (ch: string) => `$env:SM_CHANNEL='${ch}'; irm ${BASE}/sm-welcome.ps1 | iex`,
  },
];
// Simplicity left the channel pages on 2026-10-12 (Greg): no channel holds a
// sm-simplicity build, so its commands could only fail. The activation page
// /sm-simplicity/ and sm-simplicity.{sh,ps1} stay, because the SM-Activate
// email links to that page. Its old channel URLs redirect to the channel.
const RETIRED_PRODUCT_PAGES = ['sm-simplicity'];
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

// The audience markers. The installer base carries exactly one in each
// language. The wrappers carry none: they run the sm-install script of their
// own copy, so they get its audience.
const MARKERS: [RegExp, string][] = [
  [/^SM_INSTALL_AUDIENCE='internal'$/m, "SM_INSTALL_AUDIENCE='external'"],
  [/^\$SmInstallAudience = 'internal'$/m, "$SmInstallAudience = 'external'"],
];
const MARKED = ['sm-install.sh', 'sm-install.ps1'];
const PAGE_DIRS = PAGES.map((p) => p.dir);

const INT = `${SITE}/int`;
const EXT = `${SITE}/ext`;
cpSync(TREE, INT, { recursive: true });
cpSync(TREE, EXT, { recursive: true });
rmSync(TREE, { recursive: true, force: true });

// Scripts and pages only. The served docs describe both copies, so they stay as written.
const REWRITTEN = /\.(sh|ps1|html)$/;
let urls = 0;
for (const file of walk(EXT)) {
  if (!REWRITTEN.test(file)) continue;
  let text = readFileSync(file, 'utf8');
  urls += text.split(INT_DOMAIN).length - 1;
  text = text.split(INT_DOMAIN).join(EXT_DOMAIN);
  for (const [re, to] of MARKERS) text = text.replace(re, to);
  writeFileSync(file, text);
}

// The external installer refuses the staff channels, so the external pages
// for them give the commands of the INTERNAL copy (Greg, 2026-10-11): staff
// who open an external page can still install. Freelance and customers get a
// 404 from GitHub, because the channel repos control access. The command
// block is copied from the matching internal page after the rewrite above,
// so these pages keep internal URLs.
const STAFF_PAGES = [...STAFF_CHANNELS].flatMap((ch) => ['', ...PRODUCTS.map((p) => `${p.id}/`)].map((sub) => `${ch}/${sub}index.html`));
for (const rel of STAFF_PAGES) {
  const internalBlock = readFileSync(`${INT}/${rel}`, 'utf8').match(COMMANDS)?.[0];
  if (!internalBlock) throw new Error(`int/${rel} has no command block`);
  const page = `${EXT}/${rel}`;
  writeFileSync(page, readFileSync(page, 'utf8').replace(COMMANDS, () => internalBlock));
}

// Verify the effect, not the steps.
const fail = (msg: string): never => {
  throw new Error(`external copy: ${msg}`);
};
for (const name of MARKED) {
  const text = readFileSync(`${EXT}/${name}`, 'utf8');
  if (MARKERS.some(([re]) => re.test(text))) fail(`${name} still has the internal marker`);
  if (!text.includes("'external'")) fail(`${name} has no external marker`);
}
for (const dir of PAGE_DIRS) {
  const html = readFileSync(`${EXT}/${dir}/index.html`, 'utf8');
  if (!html.includes(EXT_ORIGIN)) fail(`${dir}/index.html has no external base`);
}
// Every channel, and every product on every channel, has a page in BOTH
// copies, always: <domain>/<channel>/[<product>/] are permanent URLs on
// both domains. A missing page fails the build.
const ORIGINS = { internal: INT_ORIGIN, external: EXT_ORIGIN };
for (const ch of CHANNELS) {
  for (const aud of ['internal', 'external'] as const) {
    for (const sub of ['', ...PRODUCTS.map((p) => `${p.id}/`)]) {
      const page = `${aud === 'internal' ? INT : EXT}/${ch.id}/${sub}index.html`;
      const where = `${ORIGINS[aud]}/${ch.id}/${sub}`;
      if (!existsSync(page)) throw new Error(`${where} is missing: every page must exist in both copies`);
      const html = readFileSync(page, 'utf8');
      if (!html.includes('<img class="banner"')) throw new Error(`${where} has no SimpleMotion banner`);
      if (!html.includes('<pre><code>')) throw new Error(`${where} has no install commands`);
      // Every command on a page uses one copy: the external staff pages use
      // the internal copy, and every other page uses its own copy.
      const want = aud === 'external' && !STAFF_CHANNELS.has(ch.id) ? 'external' : 'internal';
      const other = want === 'internal' ? 'external' : 'internal';
      if (!html.includes(`${ORIGINS[want]}/`) || html.includes(`${ORIGINS[other]}/`)) {
        throw new Error(`${where}: its commands must use the ${want} copy only`);
      }
    }
  }
}
const staffPageFiles = new Set(STAFF_PAGES.map((rel) => `${EXT}/${rel}`));
for (const file of walk(EXT).filter((f) => REWRITTEN.test(f) && !staffPageFiles.has(f))) {
  if (readFileSync(file, 'utf8').includes(INT_ORIGIN)) fail(`${file} still has an internal URL`);
}
// The internal copy names no external URL: the rewrite runs one way only.
for (const file of walk(INT).filter((f) => REWRITTEN.test(f))) {
  if (readFileSync(file, 'utf8').includes(EXT_ORIGIN)) throw new Error(`internal copy: ${file} has an external URL`);
}
// Azure Static Web Apps config, one per copy (Greg, 2026-10-12): each copy is
// its own SWA in rg-sm-portal-se, beside the sm-website SWAs. SWA does not
// serve this file. The MIME types keep what Pages served, except that .ps1 is
// text, so that `irm | iex` gets a string. /release redirects to /release/.
const SWA_CONFIG = {
  trailingSlash: 'auto',
  mimeTypes: {
    '.sh': 'application/x-sh',
    '.ps1': 'text/plain; charset=utf-8',
    '.md': 'text/markdown; charset=utf-8',
    // SWA sends text/html with no charset; Pages sent utf-8 (Greg, 2026-10-12).
    '.html': 'text/html; charset=utf-8',
  },
  globalHeaders: { 'X-Content-Type-Options': 'nosniff' },
  // The domain root has no page of its own: send it to the release channel.
  routes: [
    { route: '/', redirect: '/release/', statusCode: 302 },
    ...RETIRED_PRODUCT_PAGES.flatMap((p) =>
      CHANNELS.flatMap((c) =>
        [`/${c.id}/${p}`, `/${c.id}/${p}/*`].map((route) => ({ route, redirect: `/${c.id}/`, statusCode: 301 })),
      ),
    ),
  ],
};
// The SWA deploy refuses a site with no root index.html. This page is the
// fallback for a client that does not follow the route's redirect.
const ROOT_INDEX = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="0; url=release/">
<link rel="canonical" href="release/">
<title>SimpleMotion installers</title>
</head>
<body><p><a href="release/">SimpleMotion installers: release channel</a></p></body>
</html>
`;
for (const dir of [INT, EXT]) {
  writeFileSync(`${dir}/staticwebapp.config.json`, `${JSON.stringify(SWA_CONFIG, null, 2)}\n`);
  if (existsSync(`${dir}/index.html`)) throw new Error(`${dir}/index.html exists: the root redirect would replace it`);
  writeFileSync(`${dir}/index.html`, ROOT_INDEX);
}

console.log(`built ${INT} (${INT_DOMAIN}) and ${EXT} (${EXT_DOMAIN}) — ${urls} URLs changed to the external domain`);
