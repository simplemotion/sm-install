// /sm-simplicity/ setup page — interactive logic.
//
// Both installer domains serve this page. sm-build.ts writes the external
// copy for install.simplemotion.com, so customers get the external
// installer. The SM-Activate email picks the domain by recipient
// (sm_install_url::Audience::for_email): staff get .dev, customers .com.
//
// Sibling of sm-welcome/sm-welcome.ts (same card UX: ?name= greeting,
// sign-in-gated staff channels, OS detection, copy button); only the
// command built differs — the sm-simplicity installer takes its channel
// via SM_CHANNEL and needs no --email. Authored in TypeScript per the
// enterprise "always TS, never JS" rule; bundled + minified by esbuild and
// inlined into index.html at deploy time (see sm-build.ts).

import { EXTERNAL_COPY, INTERNAL_BASE, STAFF_CHANNELS, signInHref, staffSignedIn } from '../sm-channel/sm-staff.ts';

type Channel = 'release' | 'preview' | 'testing' | 'develop';
type OS = 'macOS' | 'Windows' | 'Linux';

interface CmdParts {
  /** Leading shell prefix (env-var exports), '' when none. */
  leading: string;
  /** The bash -c "$(curl …)" / irm|iex invocation. */
  head: string;
  /** Trailing args, '' on both forms here. */
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

  // Escape HTML, so that a hostile ?name= cannot put markup into innerHTML.
  const esc = (s: string): string =>
    s.replace(/[&<>"']/g, (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] as string,
    );

  // Build the command parts for the given channel. The command-substitution
  // form (not curl|bash) avoids the curl (56) race sm-simplicity.sh's header
  // documents. Channel rides on SM_CHANNEL; release needs no prefix.
  const buildCmd = (channel: Channel): CmdParts => {
    if (os === 'Windows') {
      const prefix: string[] = [];
      if (channel !== 'release') prefix.push(`$env:SM_CHANNEL="${channel}"`);
      return {
        leading: prefix.length ? `${prefix.join('; ')}; ` : '',
        head: `irm ${baseFor(channel)}/sm-simplicity.ps1 | iex`,
        tail: '',
      };
    }
    const prefix = channel !== 'release' ? `SM_CHANNEL=${channel} ` : '';
    return {
      leading: prefix,
      head: `bash -c "$(curl -fsSL ${baseFor(channel)}/sm-simplicity.sh)" sm-simplicity`,
      tail: '',
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
    // binaries (build-once/promote; see sm-welcome.ts for the full note).
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
