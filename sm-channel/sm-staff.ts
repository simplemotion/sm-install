// Shared by the page scripts: is the visitor a signed-in staff member?
//
// Both installer sites sign in with the single-tenant app registration
// sm-install-dev-signin, so only a simplemotion.com tenant account can sign
// in. The email check also refuses a guest account in that tenant.
// This only changes what the pages show. GitHub, not this check, controls
// access to the staff channels.
//
// sm-build.ts bundles this file into each page script. Like the rest of
// sm-channel/, it is not served.

// The channels that are for SimpleMotion staff only.
export const STAFF_CHANNELS: readonly string[] = ['testing', 'develop'];

// The internal copy. Keep the string in two parts, so that the build does not
// change it to the external domain in the external copy.
export const INTERNAL_BASE = ['https://install.simplemotion', 'dev'].join('.');

const STAFF_EMAIL = /@(simplemotion\.com|simplemotion\.global)$/i;

interface ClientPrincipal {
  userDetails?: string;
  userRoles?: string[];
}

// Asks the Static Web App which account has signed in. Returns false if no
// account has signed in, if the request fails, or if it is not a staff account.
export const staffSignedIn = async (): Promise<boolean> => {
  try {
    const res = await fetch('/.auth/me', { cache: 'no-store', credentials: 'same-origin' });
    if (!res.ok) return false;
    const me = (await res.json()) as { clientPrincipal?: ClientPrincipal | null };
    const p = me.clientPrincipal;
    return !!p && (p.userRoles ?? []).includes('authenticated') && STAFF_EMAIL.test(p.userDetails ?? '');
  } catch {
    return false;
  }
};

// The sign-in address. After sign-in, the visitor comes back to this page
// with its query (for example the activation email's ?email=).
export const signInHref = (): string =>
  `/.auth/login/aad?post_login_redirect_uri=${encodeURIComponent(location.pathname + location.search)}`;
