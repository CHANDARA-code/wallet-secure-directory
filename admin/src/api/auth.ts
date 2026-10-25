import { apiClient } from "./client";
import type { SessionResponse, SignInResponse } from "./types";

export async function signIn(credentials: {
  email: string;
  password: string;
}): Promise<SignInResponse> {
  return apiClient<SignInResponse>("/api/auth/sign-in/email", {
    method: "POST",
    body: JSON.stringify(credentials),
  });
}

export async function getSession(): Promise<SessionResponse | null> {
  return apiClient<SessionResponse | null>("/api/auth/get-session", {
    method: "GET",
  });
}

export async function signOut(): Promise<void> {
  await apiClient<unknown>("/api/auth/sign-out", {
    method: "POST",
    body: JSON.stringify({}),
  });
}
