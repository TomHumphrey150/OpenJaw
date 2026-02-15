const SUPABASE_PLACEHOLDER_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_PLACEHOLDER_PUBLISHABLE_KEY = 'YOUR_SUPABASE_PUBLISHABLE_KEY';
const SUPABASE_PLACEHOLDER_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

const runtimeWindow = typeof window !== 'undefined' ? window : null;
const SUPABASE_URL = runtimeWindow?.SUPABASE_URL || '';
const SUPABASE_PUBLISHABLE_KEY = runtimeWindow?.SUPABASE_PUBLISHABLE_KEY || runtimeWindow?.SUPABASE_ANON_KEY || '';

let supabase = null;

function isLocalDevHost() {
  if (!runtimeWindow?.location) return false;
  return runtimeWindow.location.hostname === 'localhost' || runtimeWindow.location.hostname === '127.0.0.1';
}

export function isSupabaseConfigured() {
  const hasPlaceholderKey =
    SUPABASE_PUBLISHABLE_KEY === SUPABASE_PLACEHOLDER_PUBLISHABLE_KEY ||
    SUPABASE_PUBLISHABLE_KEY === SUPABASE_PLACEHOLDER_ANON_KEY;

  return Boolean(
    SUPABASE_URL &&
    SUPABASE_PUBLISHABLE_KEY &&
    SUPABASE_URL !== SUPABASE_PLACEHOLDER_URL &&
    !hasPlaceholderKey
  );
}

export function initSupabase() {
  if (supabase) return supabase;

  if (!runtimeWindow?.supabase) {
    console.error('Supabase client library not loaded');
    return null;
  }

  if (!isSupabaseConfigured()) {
    console.warn('Supabase not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in config.js');
    return null;
  }

  try {
    supabase = runtimeWindow.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  } catch (error) {
    console.error('Failed to initialize Supabase client:', error);
    return null;
  }

  return supabase;
}

export function getSupabase() {
  return supabase;
}

export async function getCurrentUser() {
  if (!supabase) return null;

  const { data, error } = await supabase.auth.getUser();
  if (error) {
    const message = String(error.message || '').toLowerCase();
    if (error.name === 'AuthSessionMissingError' || message.includes('auth session missing')) {
      return null;
    }
    throw error;
  }
  return data.user;
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

export async function signInWithPassword(email, password) {
  if (!supabase) {
    console.error('Supabase not initialized');
    return { error: new Error('Supabase not initialized') };
  }

  const normalizedEmail = normalizeEmail(email);
  const normalizedPassword = String(password || '');
  if (!normalizedEmail || !normalizedPassword) {
    return { error: new Error('Email and password are required') };
  }

  const { data, error } = await supabase.auth.signInWithPassword({
    email: normalizedEmail,
    password: normalizedPassword,
  });

  return { data, error };
}

export async function signUpWithPassword(email, password) {
  if (!supabase) {
    console.error('Supabase not initialized');
    return { error: new Error('Supabase not initialized') };
  }

  const normalizedEmail = normalizeEmail(email);
  const normalizedPassword = String(password || '');
  if (!normalizedEmail || !normalizedPassword) {
    return { error: new Error('Email and password are required') };
  }

  const { data, error } = await supabase.auth.signUp({
    email: normalizedEmail,
    password: normalizedPassword,
  });

  return { data, error };
}

export async function signOut() {
  if (!supabase) {
    if (runtimeWindow?.location) runtimeWindow.location.href = '/login.html';
    return;
  }

  const { error } = await supabase.auth.signOut();
  if (error) {
    console.error('Failed to sign out:', error);
  }

  if (runtimeWindow?.location) runtimeWindow.location.href = '/login.html';
}

export async function checkAuthAndRedirect() {
  if (!supabase) {
    if (isLocalDevHost()) {
      console.warn('Auth not configured on localhost, allowing access for local development');
      return true;
    }

    if (runtimeWindow?.location) runtimeWindow.location.href = '/login.html?error=config';
    return false;
  }

  try {
    const user = await getCurrentUser();
    if (!user) {
      if (runtimeWindow?.location) runtimeWindow.location.href = '/login.html';
      return false;
    }
    return true;
  } catch (error) {
    console.error('Auth check failed:', error);
    if (runtimeWindow?.location) runtimeWindow.location.href = '/login.html?error=auth';
    return false;
  }
}

export function onAuthStateChange(callback) {
  if (!supabase) return () => {};

  const { data } = supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session);
  });

  return () => data.subscription.unsubscribe();
}
