import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ThemeProvider, useTheme } from "./ThemeProvider";

function TestConsumer() {
  const { mode, toggleTheme, setMode } = useTheme();
  return (
    <div>
      <span data-testid="theme-mode">{mode}</span>
      <button onClick={toggleTheme}>Toggle</button>
      <button onClick={() => setMode("dark")}>Set Dark</button>
      <button onClick={() => setMode("light")}>Set Light</button>
    </div>
  );
}

describe("ThemeProvider and design system theme logic", () => {
  const originalMatchMedia = window.matchMedia;

  beforeEach(() => {
    localStorage.clear();
    document.documentElement.classList.remove("dark");
    document.documentElement.style.colorScheme = "";
    document.body.style.background = "";
    vi.restoreAllMocks();
  });

  afterEach(() => {
    window.matchMedia = originalMatchMedia;
  });

  it("initializes to light mode by default and syncs document attributes", () => {
    window.matchMedia = vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }));

    render(
      <ThemeProvider>
        <TestConsumer />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("light");
    expect(document.documentElement.classList.contains("dark")).toBe(false);
    expect(document.documentElement.style.colorScheme).toBe("light");
    expect(document.body.style.background).toBe("rgb(250, 249, 245)");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("light");
  });

  it("honours saved dark value from localStorage", () => {
    localStorage.setItem("wallet_admin_theme_mode", "dark");

    render(
      <ThemeProvider>
        <TestConsumer />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("dark");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(document.documentElement.style.colorScheme).toBe("dark");
    expect(document.body.style.background).toBe("rgb(26, 25, 23)");
  });

  it("honours saved light value from localStorage even when system prefers dark", () => {
    localStorage.setItem("wallet_admin_theme_mode", "light");
    window.matchMedia = vi.fn().mockImplementation((query: string) => ({
      matches: true,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }));

    render(
      <ThemeProvider>
        <TestConsumer />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("light");
    expect(document.documentElement.classList.contains("dark")).toBe(false);
    expect(document.documentElement.style.colorScheme).toBe("light");
  });

  it("falls back to prefers-color-scheme when localStorage is empty", () => {
    window.matchMedia = vi.fn().mockImplementation((query: string) => ({
      matches: query.includes("dark"),
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }));

    render(
      <ThemeProvider>
        <TestConsumer />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("dark");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(document.documentElement.style.colorScheme).toBe("dark");
    expect(document.body.style.background).toBe("rgb(26, 25, 23)");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("dark");
  });

  it("toggling flips classList dark, colorScheme, and persists under wallet_admin_theme_mode", async () => {
    const user = userEvent.setup();
    window.matchMedia = vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }));

    render(
      <ThemeProvider>
        <TestConsumer />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("light");
    expect(document.documentElement.classList.contains("dark")).toBe(false);

    await user.click(screen.getByRole("button", { name: "Toggle" }));

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("dark");
    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(document.documentElement.style.colorScheme).toBe("dark");
    expect(document.body.style.background).toBe("rgb(26, 25, 23)");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("dark");

    await user.click(screen.getByRole("button", { name: "Toggle" }));

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("light");
    expect(document.documentElement.classList.contains("dark")).toBe(false);
    expect(document.documentElement.style.colorScheme).toBe("light");
    expect(document.body.style.background).toBe("rgb(250, 249, 245)");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("light");
  });

  it("still renders when localStorage throws", async () => {
    const user = userEvent.setup();
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("Blocked by browser storage policy");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("Blocked by browser storage policy");
    });

    render(
      <ThemeProvider>
        <TestConsumer />
      </ThemeProvider>,
    );

    expect(screen.getByTestId("theme-mode")).toHaveTextContent("light");
    await user.click(screen.getByRole("button", { name: "Toggle" }));
    expect(screen.getByTestId("theme-mode")).toHaveTextContent("dark");
  });
});
