// install.simplemotion.dev welcome page — interactive logic.
//
// Authored in TypeScript per the enterprise "always TS, never JS" rule;
// bundled + minified by esbuild and inlined into index.html at deploy time
// (see sm-build.ts + .github/workflows/sm-pages.yml). No hand-written .js.

import { EXTERNAL_COPY, INTERNAL_BASE, STAFF_CHANNELS, signInHref, staffSignedIn } from '../sm-channel/sm-staff.ts';

type Channel = 'release' | 'preview' | 'testing' | 'develop';
type OS = 'macOS' | 'Windows' | 'Linux';

interface CmdParts {
  /** Leading shell prefix (Windows env-var exports), '' on unix. */
  leading: string;
  /** The curl|bash / irm|iex invocation. */
  head: string;
  /** Trailing args (--email/--channel), '' on Windows. */
  tail: string;
}

// The base of this copy of the site. sm-build.ts writes the external domain
// here in the copy that it serves from the external domain.
const SM_INSTALL_BASE = 'https://install.simplemotion.dev';
const EXTERNAL = SM_INSTALL_BASE.endsWith('.com');
// The external installer refuses the staff channels, so a staff member on the
// external copy gets the commands of the internal copy for them.
const baseFor = (channel: string): string =>
  EXTERNAL && STAFF_CHANNELS.includes(channel) ? INTERNAL_BASE : SM_INSTALL_BASE;

(function () {
  const params = new URLSearchParams(window.location.search);
  const email = params.get('email') ?? '';
  const name = params.get('name') ?? '';

  const byId = (id: string): HTMLElement | null => document.getElementById(id);

  if (name) {
    const span = byId('name-span');
    if (span) span.textContent = `, ${name}`;
  }

  // Gate the staff channels (Testing, Develop): available only to a signed-in
  // staff member (Greg, 2026-10-14). Release and Preview are open to everyone.
  // The install.simplemotion.dev pages need sign-in, so there the staff
  // channels are always available. Others see them grayed out, with a staff
  // sign-in link.
  for (const id of ['testing-btn', 'develop-btn']) {
    byId(id)?.setAttribute('title', 'SimpleMotion staff only: sign in to use');
  }
  void staffSignedIn().then((staff) => {
    if (!staff) {
      // The internal copy is for the workforce only (Greg, 2026-10-14): there,
      // every channel and the copy button stay grayed out until sign-in.
      if (!EXTERNAL_COPY) {
        for (const b of document.querySelectorAll<HTMLButtonElement>('.channel-btn, #copy-btn')) {
          b.disabled = true;
          b.title = 'SimpleMotion staff only: sign in to use';
        }
      }
      const signIn = byId('signin');
      if (signIn instanceof HTMLAnchorElement) {
        signIn.href = signInHref();
        signIn.hidden = false;
      }
      return;
    }
    for (const id of ['testing-btn', 'develop-btn']) {
      const b = byId(id);
      if (b) {
        (b as HTMLButtonElement).disabled = false;
        b.removeAttribute('title');
      }
    }
  });

  const ua = navigator.userAgent;
  const os: OS = /Mac/i.test(ua) ? 'macOS' : /Win/i.test(ua) ? 'Windows' : 'Linux';
  const arch = /aarch64|arm64/i.test(ua) || os === 'macOS' ? 'aarch64' : 'x86_64';

  const setText = (id: string, text: string): void => {
    const el = byId(id);
    if (el) el.textContent = text;
  };
  setText('platform', `Detected: ${os}`);
  setText('cmd-os', os);
  setText('cmd-arch', arch);

  // Escape HTML so a hostile ?email=/?name= can't inject markup via innerHTML.
  const esc = (s: string): string =>
    s.replace(/[&<>"']/g, (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string,
    );

  // Build the command parts for the given channel. Windows uses an
  // env-var prefix + irm|iex; unix uses curl|bash with --flags.
  const buildCmd = (channel: Channel): CmdParts => {
    if (os === 'Windows') {
      const prefix: string[] = [];
      if (email) prefix.push(`$env:SM_EMAIL="${email}"`);
      prefix.push(`$env:SM_CHANNEL="${channel}"`);
      return {
        leading: `${prefix.join('; ')}; `,
        head: `irm ${baseFor(channel)}/sm-welcome.ps1 | iex`,
        tail: '',
      };
    }
    let args = '';
    if (email) args += `--email ${email} `;
    args += `--channel ${channel}`;
    return {
      leading: '',
      head: `curl -fsSL ${baseFor(channel)}/sm-welcome.sh | bash -s --`,
      tail: args,
    };
  };

  const setChannel = (channel: Channel): void => {
    document.querySelectorAll<HTMLButtonElement>('.channel-btn').forEach((b) => {
      b.classList.toggle('active', b.dataset.channel === channel);
    });
    const parts = buildCmd(channel);
    const cmdEl = byId('cmd');
    if (cmdEl) {
      let html = `<span class="cmd-line">${esc(parts.leading)}${esc(parts.head)}`;
      if (parts.tail) html += `<br>${esc(parts.tail)}`;
      html += '</span>';
      cmdEl.innerHTML = html;
      cmdEl.dataset.copy = parts.leading + parts.head + (parts.tail ? ` ${parts.tail}` : '');
    }

    // Verify glyph: every channel ships the SAME SHA256'd + SLSA-attested
    // binaries. Under the build-once/promote model, develop is where CI
    // builds and signs them; testing/preview/release are byte-identical
    // promotions of those exact artifacts (verified — cosign
    // verify-blob-attestation against the sm-ci signer identity passes on
    // develop just as it does on release). So sha256 + attestation is ✓ on
    // all four channels. (Channel maturity — pre-release vs GA — is what the
    // channel tabs convey; it is not an integrity distinction.)
    const verifyEl = byId('cmd-verify');
    if (verifyEl) {
      verifyEl.classList.add('ok');
      verifyEl.classList.remove('fail');
    }
  };

  document.querySelectorAll<HTMLButtonElement>('.channel-btn').forEach((b) => {
    b.addEventListener('click', () => {
      if (b.disabled) return;
      setChannel((b.dataset.channel as Channel) ?? 'release');
    });
  });

  // Copy button (wired here rather than an inline onclick so the bundle
  // needs no global symbols).
  const copyBtn = byId('copy-btn');
  if (copyBtn) {
    copyBtn.addEventListener('click', () => {
      const cmdEl = byId('cmd');
      const text = cmdEl?.dataset.copy ?? cmdEl?.textContent ?? '';
      void navigator.clipboard.writeText(text).then(() => {
        copyBtn.classList.add('copied');
        setTimeout(() => copyBtn.classList.remove('copied'), 1800);
      });
    });
  }

  setChannel('release');
})();
