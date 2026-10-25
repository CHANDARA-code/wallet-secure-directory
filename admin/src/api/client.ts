import type { ApiErrorPayload } from "./types";

export class ApiError extends Error {
  readonly statusCode: number;
  readonly errorName: string;
  readonly messages: string[];

  constructor(statusCode: number, errorName: string, messages: string[]) {
    super(messages.join(", ") || errorName || `HTTP error ${statusCode}`);
    this.name = "ApiError";
    this.statusCode = statusCode;
    this.errorName = errorName;
    this.messages = messages;
  }
}

type UnauthorizedListener = () => void;

let globalUnauthorizedListener: UnauthorizedListener | null = null;

export function setUnauthorizedListener(
  listener: UnauthorizedListener | null,
): void {
  globalUnauthorizedListener = listener;
}

export async function apiClient<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const headers = new Headers(options.headers);

  if (
    !headers.has("Content-Type") &&
    options.body &&
    typeof options.body === "string"
  ) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(path, {
    ...options,
    credentials: "include",
    headers,
  });

  if (response.status === 401) {
    if (path !== "/api/auth/get-session") {
      globalUnauthorizedListener?.();
    }
  }

  if (!response.ok) {
    let errorPayload: ApiErrorPayload | null = null;
    try {
      errorPayload = (await response.json()) as ApiErrorPayload;
    } catch {
      errorPayload = null;
    }

    if (errorPayload) {
      const messages = Array.isArray(errorPayload.message)
        ? errorPayload.message
        : errorPayload.message
          ? [errorPayload.message]
          : [errorPayload.error || response.statusText || "Request failed"];

      throw new ApiError(
        errorPayload.statusCode || response.status,
        errorPayload.error || response.statusText || "Error",
        messages,
      );
    }

    throw new ApiError(response.status, response.statusText || "Error", [
      response.statusText || `Request failed with status ${response.status}`,
    ]);
  }

  if (response.status === 204) {
    return undefined as unknown as T;
  }

  const contentType = response.headers.get("content-type");
  if (contentType && contentType.includes("application/json")) {
    return (await response.json()) as T;
  }

  return (await response.text()) as unknown as T;
}
