"use client";

import { useState } from "react";

interface User {
  name: string | null;
  email: string | null;
  image: string | null;
}

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}

interface StoredSession {
  idToken: string;
  accessToken: string;
  expiresAt: number;
}

interface PkceState {
  state: string;
  codeVerifier: string;
}

const SESSION_STORAGE_KEY = "oauth2.cognito.session";
const PKCE_STORAGE_KEY = "oauth2.cognito.pkce";

function getConfig() {
  const domain = (process.env.NEXT_PUBLIC_COGNITO_DOMAIN ?? "")
    .replace(/^https?:\/\//, "")
    .replace(/\/$/, "");
  const clientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? "";
  const redirectUri = process.env.NEXT_PUBLIC_COGNITO_REDIRECT_URI ?? "";
  const logoutUri = process.env.NEXT_PUBLIC_COGNITO_LOGOUT_URI ?? "";

  if (!domain || !clientId || !redirectUri || !logoutUri) {
    throw new Error(
      "Missing Cognito env vars. Set NEXT_PUBLIC_COGNITO_DOMAIN, NEXT_PUBLIC_COGNITO_CLIENT_ID, NEXT_PUBLIC_COGNITO_REDIRECT_URI, and NEXT_PUBLIC_COGNITO_LOGOUT_URI.",
    );
  }

  return { domain, clientId, redirectUri, logoutUri };
}

function base64UrlEncode(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chars = Array.from(bytes, (b) => String.fromCharCode(b)).join("");

  return btoa(chars)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function createRandomString(length: number): string {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

async function createPkceChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );
  return base64UrlEncode(digest);
}

function parseJwtPayload(token: string): Record<string, unknown> {
  const payload = token.split(".")[1];
  if (!payload) {
    throw new Error("Invalid token format");
  }

  const normalized = payload.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const json = atob(padded);
  return JSON.parse(json) as Record<string, unknown>;
}

function clearSession(): void {
  sessionStorage.removeItem(SESSION_STORAGE_KEY);
  sessionStorage.removeItem(PKCE_STORAGE_KEY);
}

function readSession(): StoredSession | null {
  const raw = sessionStorage.getItem(SESSION_STORAGE_KEY);
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw) as StoredSession;
  } catch {
    clearSession();
    return null;
  }
}

function sessionToUser(session: StoredSession): User | null {
  try {
    const payload = parseJwtPayload(session.idToken);
    return {
      name: typeof payload.name === "string" ? payload.name : null,
      email: typeof payload.email === "string" ? payload.email : null,
      image: typeof payload.picture === "string" ? payload.picture : null,
    };
  } catch {
    return null;
  }
}

function buildInitialAuthState(): AuthState {
  if (typeof window === "undefined") {
    return {
      user: null,
      isAuthenticated: false,
      isLoading: true,
    };
  }

  const session = readSession();
  if (!session) {
    return {
      user: null,
      isAuthenticated: false,
      isLoading: false,
    };
  }

  if (Date.now() >= session.expiresAt * 1000) {
    clearSession();
    return {
      user: null,
      isAuthenticated: false,
      isLoading: false,
    };
  }

  return {
    user: sessionToUser(session),
    isAuthenticated: true,
    isLoading: false,
  };
}

export function useAuth(): AuthState {
  const [state] = useState<AuthState>(() => buildInitialAuthState());

  return state;
}

export async function signIn(provider: "google") {
  if (provider !== "google") {
    throw new Error("Only Google sign-in is currently enabled.");
  }

  const { domain, clientId, redirectUri } = getConfig();

  const codeVerifier = createRandomString(96);
  const codeChallenge = await createPkceChallenge(codeVerifier);
  const state = createRandomString(48);

  const pkceState: PkceState = { state, codeVerifier };
  sessionStorage.setItem(PKCE_STORAGE_KEY, JSON.stringify(pkceState));

  const authorizeUrl = new URL(`https://${domain}/oauth2/authorize`);
  authorizeUrl.searchParams.set("identity_provider", "Google");
  authorizeUrl.searchParams.set("client_id", clientId);
  authorizeUrl.searchParams.set("response_type", "code");
  authorizeUrl.searchParams.set("scope", "openid email profile");
  authorizeUrl.searchParams.set("redirect_uri", redirectUri);
  authorizeUrl.searchParams.set("state", state);
  authorizeUrl.searchParams.set("code_challenge_method", "S256");
  authorizeUrl.searchParams.set("code_challenge", codeChallenge);

  window.location.assign(authorizeUrl.toString());
}

export async function completeSignInFromCallback(): Promise<{
  ok: boolean;
  error?: string;
}> {
  const { domain, clientId, redirectUri } = getConfig();
  const params = new URLSearchParams(window.location.search);

  const oauthError = params.get("error");
  if (oauthError) {
    const desc = params.get("error_description") ?? "OAuth2 callback failed";
    return { ok: false, error: `${oauthError}: ${desc}` };
  }

  const code = params.get("code");
  const state = params.get("state");
  if (!code || !state) {
    return { ok: false, error: "Missing code/state from OAuth2 callback" };
  }

  const rawPkce = sessionStorage.getItem(PKCE_STORAGE_KEY);
  if (!rawPkce) {
    return { ok: false, error: "Missing PKCE verifier in browser session" };
  }

  let pkceState: PkceState;
  try {
    pkceState = JSON.parse(rawPkce) as PkceState;
  } catch {
    return { ok: false, error: "Corrupt PKCE state in browser session" };
  }

  if (pkceState.state !== state) {
    return { ok: false, error: "OAuth2 state mismatch" };
  }

  const tokenBody = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientId,
    redirect_uri: redirectUri,
    code,
    code_verifier: pkceState.codeVerifier,
  });

  const tokenRes = await fetch(`https://${domain}/oauth2/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: tokenBody.toString(),
  });

  if (!tokenRes.ok) {
    const rawError = await tokenRes.text();
    return { ok: false, error: `Token exchange failed: ${rawError}` };
  }

  const tokenJson = (await tokenRes.json()) as {
    access_token?: string;
    id_token?: string;
  };

  if (!tokenJson.access_token || !tokenJson.id_token) {
    return { ok: false, error: "Token exchange returned missing tokens" };
  }

  const idPayload = parseJwtPayload(tokenJson.id_token);
  const exp = idPayload.exp;
  if (typeof exp !== "number") {
    return { ok: false, error: "Missing exp claim in id_token" };
  }

  const session: StoredSession = {
    idToken: tokenJson.id_token,
    accessToken: tokenJson.access_token,
    expiresAt: exp,
  };

  sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
  sessionStorage.removeItem(PKCE_STORAGE_KEY);
  return { ok: true };
}

export function signOut() {
  const { domain, clientId, logoutUri } = getConfig();
  clearSession();

  const logoutUrl = new URL(`https://${domain}/logout`);
  logoutUrl.searchParams.set("client_id", clientId);
  logoutUrl.searchParams.set("logout_uri", logoutUri);

  window.location.assign(logoutUrl.toString());
}

export function getAccessToken(): string | null {
  const session = readSession();
  if (!session) {
    return null;
  }

  if (Date.now() >= session.expiresAt * 1000) {
    clearSession();
    return null;
  }

  return session.accessToken;
}

export function getIdToken(): string | null {
  const session = readSession();
  if (!session) {
    return null;
  }

  if (Date.now() >= session.expiresAt * 1000) {
    clearSession();
    return null;
  }

  return session.idToken;
}
