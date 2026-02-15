# Changes Made for Vercel + Supabase Deployment

This document details the migration from a local Express server to a Vercel-hosted app with Supabase authentication.

---

## 1. Created `/api/` Directory with Serverless Functions

### Files Created:
- `api/interventions.ts`
- `api/bruxism-info.ts`
- `api/health.ts`

### Why:
Vercel uses file-based routing for serverless functions. Each file in `/api/` is deployed as an endpoint:
- `/api/interventions.ts` -> `GET /api/interventions`
- `/api/bruxism-info.ts` -> `GET /api/bruxism-info`
- `/api/health.ts` -> `GET /api/health`

This replaces the local Express API routes in `src/server.ts`.

---

## 2. Created `vercel.json`

### Why:
Configures static output for Vercel:
- `outputDirectory: "public"` - serves static assets from `public/`
- No custom rewrites are needed because Vercel handles `/api/*` natively from the `api/` directory

---

## 3. Updated `package.json`

### Changes:
- Added `@supabase/supabase-js` dependency
- Added `@vercel/node` and `vercel` development dependencies
- Added `dev:vercel` script for local Vercel emulation
- Switched `dev:vercel` to `npx --yes vercel@latest dev` so local dev consistently uses npm instead of stale CLI yarn detection
- Added `test` / `test:all` scripts for full regression coverage

### Why:
- Supabase client powers authentication
- Vercel packages support serverless TypeScript routes and local testing
- Full test scripts reduce regression risk for auth/bootstrap logic

---

## 4. Created `public/js/config.js`

### Why:
Provides a single location for Supabase credentials:

```javascript
window.SUPABASE_URL = 'YOUR_SUPABASE_URL';
window.SUPABASE_PUBLISHABLE_KEY = 'YOUR_SUPABASE_PUBLISHABLE_KEY';

// Optional backward compatibility alias:
window.SUPABASE_ANON_KEY = window.SUPABASE_PUBLISHABLE_KEY;
```

---

## 5. Created and Hardened `public/js/auth.js`

### Why:
Centralizes authentication behavior:
- `initSupabase()` - creates the Supabase client
- `getCurrentUser()` - fetches current session user
- `signInWithPassword(email, password)` - email/password sign-in
- `signUpWithPassword(email, password)` - email/password account creation
- `signOut()` - signs out and returns to login
- `checkAuthAndRedirect()` - blocks unauthenticated access

Key handling:
- Primary browser key is `SUPABASE_PUBLISHABLE_KEY` (new Supabase API key format)
- Legacy `SUPABASE_ANON_KEY` is still accepted as fallback

Additional hardening:
- Deployed environments are fail-safe (missing config redirects to login)
- Localhost keeps a dev bypass when Supabase is intentionally unset
- Auth API errors are handled and redirected with explicit error states

---

## 6. Created `public/login.html` and `public/js/login.js`

### Why:
Moves login behavior into a testable module and supports email/password auth:
- Email + password fields
- `Sign In` action
- `Create Account` action
- Loading, error, and status messaging
- Auto-redirect to app when a valid session already exists

---

## 7. Updated `public/index.html`

### Changes:
- Added Supabase CDN and config script in `<head>`
- Pinned Supabase CDN version (`2.95.3`) to avoid silent behavior drift
- Updated legacy server-error copy to deployment-neutral language
- Added footer sign-out button

---

## 8. Updated `public/js/app.js`

### Changes:
- Added auth check before health/data fetch
- Added sign-out button wiring
- Added error handling around sign-out failures
- Introduced dependency injection seams for integration testing

### Why:
Protects app routes and enables deterministic tests without browser-only globals.

---

## 9. Updated `public/css/styles.css`

### Changes:
- Added `.footer-buttons` layout for `Data` + `Sign Out` buttons

### Why:
Keeps footer actions aligned and responsive.

---

## 10. Added Regression Tests (Unit + Integration)

### New files:
- `test/auth.unit.test.mjs`
- `test/login.integration.test.mjs`
- `test/app.integration.test.mjs`
- `test/vercelConfig.unit.test.mjs`
- `test/helpers/domMock.mjs`

### Why:
Covers the exact failure modes fixed in this migration:
- missing auth config handling
- auth redirect behavior
- sign-out failure behavior
- login page error/status handling
- vercel config regression guard (no accidental rewrite reintroduction)

---

## Architecture Summary

### Before (Local Express Server)

```
Request -> Express Server -> Read JSON files -> Response
                ↓
         Serve static files from /public
```

### After (Vercel + Supabase)

```
Request -> Vercel Edge Network
              ↓
    ┌─────────┴─────────┐
    ↓                   ↓
Static files        /api/* routes
from /public        (serverless functions)
    ↓                   ↓
 Browser            JSON response
    ↓
Supabase Auth
(Email + Password)
```

---

## What Still Works

- Local Express development via `npm run dev`
- Existing dashboard features (causal graph, defense check-ins, import/export)
- localStorage data model (not yet migrated to Supabase database)

---

## Future Enhancements (Not Implemented)

1. Store user data in Supabase tables instead of localStorage
2. Add row-level security rules for per-user isolation
3. Sync data across devices
4. Add password reset and account settings UI
