# Deploying Bruxism Dashboard to Vercel + Supabase

## Overview
- **Vercel**: Hosts the frontend and serverless API functions
- **Supabase**: Provides email/password authentication (and optional database)

## Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign up/sign in
2. Click "New Project"
3. Name it something like "bruxism-dashboard"
4. Choose a strong database password (save it)
5. Select a region close to you
6. Click "Create new project" and wait for setup

## Step 2: Enable Email/Password Auth in Supabase

1. In Supabase, go to **Authentication** > **Providers**
2. Open **Email** and ensure it is enabled
3. For easiest initial setup, disable **Confirm email** so newly-created accounts can sign in immediately
4. Save your provider settings

Note: If you keep email confirmation enabled, users can still create accounts, but must verify email before login succeeds.

## Step 2b: Create or Confirm a Test User

Before using **Sign In**, make sure at least one valid user exists:

1. Use **Create Account** on `/login.html`, or add a user under **Authentication** > **Users**
2. If email confirmation is enabled, verify the user email first

## Step 3: Get Supabase Keys

1. In Supabase dashboard, go to **Settings** > **API**
2. Copy these values:
   - **Project URL** (looks like `https://xxxxx.supabase.co`)
   - **Publishable key** from **API Keys** (starts with `sb_publishable_`)

If your project still shows legacy keys, you can use the legacy `anon` key. This app supports both.

## Step 4: Configure the App

Edit `public/js/config.js`:

```javascript
window.SUPABASE_URL = 'https://YOUR_PROJECT_REF.supabase.co';
window.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_xxx';

// Optional backward compatibility alias:
window.SUPABASE_ANON_KEY = window.SUPABASE_PUBLISHABLE_KEY;
```

## Step 5: Deploy to Vercel

### Option A: Via CLI
```bash
npx vercel login
npx vercel
```

### Option B: Via GitHub
1. Push your code to GitHub
2. Go to [vercel.com](https://vercel.com)
3. Click "Import Project"
4. Select your GitHub repo
5. Vercel will auto-detect settings from `vercel.json`
6. Click "Deploy"

## Step 6: Configure Supabase URL Settings (After Deployment)

Once Vercel gives you your real deployment URL:

1. In Supabase, open **Authentication** > **URL Configuration**
2. Set **Site URL**:
   ```
   https://your-app.vercel.app
   ```
3. Add these entries to **Redirect URLs**:
   ```
   https://your-app.vercel.app/**
   http://localhost:3000/**
   ```

## Testing Locally

```bash
npm install
npm run dev:vercel
```

This runs the Vercel dev server locally at http://localhost:3000.
`dev:vercel` uses the latest Vercel CLI via `npx` to avoid older CLI package-manager detection bugs.

## Troubleshooting

### "Supabase not configured" warning
- Check that `config.js` has both the correct URL and publishable key
- On deployed environments, missing values block login (expected fail-safe behavior)

### Account creation works but login fails
- If email confirmation is enabled, verify the account email first
- Or disable **Confirm email** in Supabase Email provider while iterating

### "Invalid login credentials"
- Confirm the email/password pair is correct
- Ensure the user exists under Supabase **Authentication** > **Users**
- If this is your first login, click **Create Account** in the app first (or add a user from Supabase **Authentication** > **Users**)

### Supabase `/auth/v1/token?grant_type=password` returns 400
- This is usually a configuration or credentials issue, not a localhost issue
- Check **Authentication** > **Providers** > **Email**:
  - Email provider enabled
  - Password login enabled
  - For easiest local testing, disable **Confirm email**
- If **Confirm email** is enabled, complete email verification before signing in
- Verify `public/js/config.js` uses the correct project URL + publishable key for the same Supabase project

### API returns 404
- Ensure `api/` folder exists with `.ts` files
- Check Vercel deployment logs

### `sh: yarn: command not found` during `vercel dev`
- Run `npm run dev:vercel` (this uses `npx --yes vercel@latest dev`)
- If you run `vercel dev` directly, update your CLI first: `npm i -D vercel@latest`

## Optional: Add Database Storage

Currently data is stored in browser localStorage. To sync across devices:

1. In Supabase, go to **Table Editor**
2. Create tables for your data (user_settings, check_ins, etc.)
3. Set up Row Level Security (RLS) so users only see their own data
4. Update the storage.js module to use Supabase client instead of localStorage
