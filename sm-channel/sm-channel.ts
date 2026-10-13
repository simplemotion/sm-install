// Channel and product pages — interactive logic.
//
// 1. The copy button beside each install command.
// 2. The locked channels in the channel nav. sm-build.ts writes the staff
//    channels (Testing, Develop) grayed out. On the internal copy, this script
//    also grays out Release and Preview, and turns off the copy buttons, until
//    a staff member signs in. It shows a staff sign-in link until then.
//
// sm-build.ts bundles and minifies this script with esbuild, and puts it in
// each page.
// Do not write a domain here: the build changes it in the external copy.

import { EXTERNAL_COPY, LOCKED_CHANNELS, signInHref, staffSignedIn } from './sm-staff.ts';

(function () {
  const LOCKED_TITLE = 'SimpleMotion staff only: sign in to open';
  const copyButtons = document.querySelectorAll<HTMLButtonElement>('.copy');
  const navLinks = document.querySelectorAll<HTMLAnchorElement>('.nav a[data-channel]');

  for (const btn of copyButtons) {
    btn.addEventListener('click', () => {
      if (btn.disabled) return;
      const text = btn.parentElement?.querySelector('code')?.textContent ?? '';
      void navigator.clipboard.writeText(text).then(() => {
        btn.classList.add('copied');
        btn.textContent = 'Copied';
        setTimeout(() => {
          btn.classList.remove('copied');
          btn.textContent = 'Copy';
        }, 1800);
      });
    });
  }

  // A grayed-out channel does not open. On the external copy the page itself
  // stays public, so a visitor with no script can still open it.
  for (const a of navLinks) {
    a.addEventListener('click', (e) => {
      if (a.classList.contains('locked')) e.preventDefault();
    });
  }

  void staffSignedIn().then((staff) => {
    if (staff) {
      for (const a of navLinks) {
        a.classList.remove('locked');
        a.removeAttribute('aria-disabled');
        a.removeAttribute('tabindex');
        a.removeAttribute('title');
      }
      return;
    }
    // The current channel stays highlighted, not grayed out.
    for (const a of navLinks) {
      if (a.classList.contains('active') || !LOCKED_CHANNELS.includes(a.dataset.channel ?? '')) continue;
      a.classList.add('locked');
      a.setAttribute('aria-disabled', 'true');
      a.setAttribute('tabindex', '-1');
      a.setAttribute('title', LOCKED_TITLE);
    }
    if (!EXTERNAL_COPY) {
      for (const btn of copyButtons) {
        btn.disabled = true;
        btn.title = LOCKED_TITLE;
      }
    }
    const signIn = document.getElementById('signin');
    if (signIn instanceof HTMLAnchorElement) {
      signIn.href = signInHref();
      signIn.hidden = false;
    }
  });
})();
