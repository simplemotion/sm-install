// Channel and product pages — interactive logic.
//
// 1. The copy button beside each install command.
// 2. The staff channels (Testing, Develop) in the channel nav. sm-build.ts
//    writes them grayed out. This script makes them available when a staff
//    member has signed in. Otherwise it shows a staff sign-in link.
//
// sm-build.ts bundles and minifies this script with esbuild, and puts it in
// each page.
// Do not write a domain here: the build changes it in the external copy.

import { signInHref, staffSignedIn } from './sm-staff.ts';

(function () {
  for (const btn of document.querySelectorAll<HTMLButtonElement>('.copy')) {
    btn.addEventListener('click', () => {
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

  // A grayed-out channel does not open. The page itself stays public, so a
  // visitor with no script can still open it.
  for (const a of document.querySelectorAll<HTMLAnchorElement>('.nav a.locked')) {
    a.addEventListener('click', (e) => {
      if (a.classList.contains('locked')) e.preventDefault();
    });
  }

  void staffSignedIn().then((staff) => {
    if (staff) {
      for (const a of document.querySelectorAll<HTMLAnchorElement>('.nav a.locked')) {
        a.classList.remove('locked');
        a.removeAttribute('aria-disabled');
        a.removeAttribute('tabindex');
        a.removeAttribute('title');
      }
      return;
    }
    const signIn = document.getElementById('signin');
    if (signIn instanceof HTMLAnchorElement) {
      signIn.href = signInHref();
      signIn.hidden = false;
    }
  });
})();
