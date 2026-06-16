// install.simplemotion.com welcome page — interactive logic.
//
// Authored in TypeScript per the enterprise "always TS, never JS" rule;
// bundled + minified by esbuild and inlined into index.html at deploy time
// (see sm-build.ts + .github/workflows/sm-pages.yml). No hand-written .js.

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

(function () {
  const params = new URLSearchParams(window.location.search);
  const email = params.get('email') ?? '';
  const name = params.get('name') ?? '';

  const byId = (id: string): HTMLElement | null => document.getElementById(id);

  if (name) {
    const span = byId('name-span');
    if (span) span.textContent = `, ${name}`;
  }

  // Gate the internal channels (Testing, Develop): enabled only for
  // simplemotion.com / simplemotion.global accounts. Others see them
  // disabled with an explanatory tooltip.
  const internalAllowed = /@(simplemotion\.com|simplemotion\.global)$/i.test(email);
  if (internalAllowed) {
    for (const id of ['testing-btn', 'develop-btn']) {
      const b = byId(id);
      if (b) {
        (b as HTMLButtonElement).disabled = false;
        b.removeAttribute('title');
      }
    }
  }

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
        head: 'irm https://install.simplemotion.com/sm-welcome.ps1 | iex',
        tail: '',
      };
    }
    let args = '';
    if (email) args += `--email ${email} `;
    args += `--channel ${channel}`;
    return {
      leading: '',
      head: 'curl -fsSL https://install.simplemotion.com/sm-welcome.sh | bash -s --',
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

    // Verify glyph: release + preview ship sha256 + SLSA attestation (green
    // ✓). testing + develop are unverified internal builds (red ✗).
    const verifyEl = byId('cmd-verify');
    if (verifyEl) {
      const unverified = channel === 'testing' || channel === 'develop';
      verifyEl.classList.toggle('fail', unverified);
      verifyEl.classList.toggle('ok', !unverified);
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
