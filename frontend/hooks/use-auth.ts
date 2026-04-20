"use client";

import { useEffect, useState } from "react";

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

// TODO: Replace with real auth calls to your backend API
export function useAuth(): AuthState {
  const [state, setState] = useState<AuthState>({
    user: null,
    isAuthenticated: false,
    isLoading: true,
  });

  useEffect(() => {
    // Stub: simulate checking auth state
    setState({
      user: {
        name: "Demo User",
        email: "demo@example.com",
        image: null,
      },
      isAuthenticated: true,
      isLoading: false,
    });
  }, []);

  return state;
}

// TODO: Replace with real sign-in via your backend OAuth flow
export function signIn(provider: "google" | "twitter") {
  console.log(`Sign in with ${provider} — wire to backend`);
}

// TODO: Replace with real sign-out via your backend
export function signOut() {
  console.log("Sign out — wire to backend");
}
