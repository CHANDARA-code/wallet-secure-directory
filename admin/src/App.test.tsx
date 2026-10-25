import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { App } from "./App";

describe("App authentication and access control", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("login form submits credentials and shows an error on 401", async () => {
    const user = userEvent.setup();

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url.includes("/api/auth/get-session")) {
        return Promise.resolve(
          new Response(JSON.stringify(null), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }

      if (url.includes("/api/auth/sign-in/email")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              statusCode: 401,
              message: "Invalid credentials",
              error: "Unauthorized",
            }),
            {
              status: 401,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      }

      return Promise.reject(new Error(`Unexpected fetch: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    const emailInput = await screen.findByPlaceholderText("admin@example.com");
    const passwordInput = screen.getByPlaceholderText("Password");
    const submitButton = screen.getByRole("button", { name: /sign in/i });

    await user.type(emailInput, "admin@example.com");
    await user.type(passwordInput, "wrongpassword");
    await user.click(submitButton);

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/auth/sign-in/email",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({
            email: "admin@example.com",
            password: "wrongpassword",
          }),
        }),
      );
    });

    expect(await screen.findByText("Invalid credentials")).toBeInTheDocument();
  });

  it("a non-admin session renders the access-required screen and never calls /api/admin/*", async () => {
    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url.includes("/api/auth/get-session")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              session: {
                id: "sess-123",
                userId: "user-standard",
                expiresAt: "2026-12-31T23:59:59.000Z",
              },
              user: {
                id: "user-standard",
                name: "Standard User",
                email: "user@example.com",
                emailVerified: true,
                role: "user",
                createdAt: "2026-01-01T00:00:00.000Z",
                updatedAt: "2026-01-01T00:00:00.000Z",
              },
            }),
            {
              status: 200,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      }

      return Promise.resolve(
        new Response(JSON.stringify({}), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    expect(
      await screen.findByText("Admin access required"),
    ).toBeInTheDocument();
    expect(
      screen.getByText(
        "Your account does not have administrator privileges. Please sign in with an administrator account.",
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /sign out/i }),
    ).toBeInTheDocument();

    const adminApiCalls = fetchMock.mock.calls.filter((call) => {
      const url = String(call[0]);
      return url.includes("/api/admin");
    });

    expect(adminApiCalls).toHaveLength(0);
  });

  it("renders theme toggle on login page and flips document attributes and localStorage", async () => {
    const user = userEvent.setup();
    localStorage.clear();
    document.documentElement.classList.remove("dark");
    document.documentElement.style.colorScheme = "";

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/auth/get-session")) {
        return Promise.resolve(
          new Response(JSON.stringify(null), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }
      return Promise.reject(new Error(`Unexpected fetch: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    const toggleButton = await screen.findByRole("button", {
      name: /switch to dark mode/i,
    });
    expect(toggleButton).toBeInTheDocument();
    expect(document.documentElement.classList.contains("dark")).toBe(false);

    await user.click(toggleButton);

    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(document.documentElement.style.colorScheme).toBe("dark");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("dark");

    const lightToggleButton = screen.getByRole("button", {
      name: /switch to light mode/i,
    });
    expect(lightToggleButton).toBeInTheDocument();

    await user.click(lightToggleButton);

    expect(document.documentElement.classList.contains("dark")).toBe(false);
    expect(document.documentElement.style.colorScheme).toBe("light");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("light");
  });

  it("still renders the app when localStorage throws on access", async () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("SecurityError: Access to storage is denied");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("SecurityError: Access to storage is denied");
    });

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/auth/get-session")) {
        return Promise.resolve(
          new Response(JSON.stringify(null), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }
      return Promise.reject(new Error(`Unexpected fetch: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    expect(await screen.findByText("Admin Portal")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /switch to dark mode/i }),
    ).toBeInTheDocument();
  });

  it("unmounts page state on sign out so a subsequent admin with a pending fetch sees no previous rows", async () => {
    const user = userEvent.setup();

    let currentAdminSession: {
      session: { id: string; userId: string; expiresAt: string };
      user: {
        id: string;
        name: string;
        email: string;
        emailVerified: boolean;
        role: string;
        createdAt: string;
        updatedAt: string;
      };
    } | null = {
      session: {
        id: "sess-admin-1",
        userId: "admin-1",
        expiresAt: "2026-12-31T23:59:59.000Z",
      },
      user: {
        id: "admin-1",
        name: "First Admin",
        email: "admin1@example.com",
        emailVerified: true,
        role: "admin",
        createdAt: "2026-01-01T00:00:00.000Z",
        updatedAt: "2026-01-01T00:00:00.000Z",
      },
    };

    let usersFetchNeverResolves = false;

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url.includes("/api/auth/get-session")) {
        return Promise.resolve(
          new Response(JSON.stringify(currentAdminSession), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }

      if (url.includes("/api/auth/sign-out")) {
        currentAdminSession = null;
        return Promise.resolve(
          new Response(JSON.stringify({ success: true }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }

      if (url.includes("/api/auth/sign-in/email")) {
        currentAdminSession = {
          session: {
            id: "sess-admin-2",
            userId: "admin-2",
            expiresAt: "2026-12-31T23:59:59.000Z",
          },
          user: {
            id: "admin-2",
            name: "Second Admin",
            email: "admin2@example.com",
            emailVerified: true,
            role: "admin",
            createdAt: "2026-01-01T00:00:00.000Z",
            updatedAt: "2026-01-01T00:00:00.000Z",
          },
        };
        usersFetchNeverResolves = true;
        return Promise.resolve(
          new Response(JSON.stringify(currentAdminSession), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }

      if (url.includes("/api/admin/users")) {
        if (usersFetchNeverResolves) {
          return new Promise(() => {});
        }
        return Promise.resolve(
          new Response(
            JSON.stringify({
              items: [
                {
                  id: "user-alpha",
                  name: "Citizen Alpha Previous Admin Row",
                  email: "citizen.alpha@example.com",
                  role: "user",
                  createdAt: "2026-01-01T00:00:00.000Z",
                  documentCount: 3,
                },
              ],
              total: 1,
            }),
            {
              status: 200,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      }

      return Promise.reject(new Error(`Unexpected fetch: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<App />);

    expect(await screen.findByText("First Admin")).toBeInTheDocument();
    expect(
      await screen.findByText("Citizen Alpha Previous Admin Row"),
    ).toBeInTheDocument();

    const signOutButton = screen.getByRole("button", { name: /sign out/i });
    await user.click(signOutButton);

    const emailInput = await screen.findByPlaceholderText("admin@example.com");
    const passwordInput = screen.getByPlaceholderText("Password");
    const signInButton = screen.getByRole("button", { name: /sign in/i });

    expect(
      screen.queryByText("Citizen Alpha Previous Admin Row"),
    ).not.toBeInTheDocument();

    await user.type(emailInput, "admin2@example.com");
    await user.type(passwordInput, "validpassword");
    await user.click(signInButton);

    expect(await screen.findByText("Second Admin")).toBeInTheDocument();
    expect(
      screen.queryByText("Citizen Alpha Previous Admin Row"),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByText("citizen.alpha@example.com"),
    ).not.toBeInTheDocument();
  });
});
