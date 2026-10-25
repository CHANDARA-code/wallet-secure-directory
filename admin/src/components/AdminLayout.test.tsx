import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AdminLayout } from "./AdminLayout";
import { ThemeProvider } from "../theme/ThemeProvider";
import type { User } from "../api/types";

const mockAdminUser: User = {
  id: "user-admin",
  name: "Admin User",
  email: "admin@example.com",
  emailVerified: true,
  role: "admin",
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:00.000Z",
};

describe("AdminLayout component", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.classList.remove("dark");
    document.documentElement.style.colorScheme = "";
    vi.restoreAllMocks();
  });

  it("renders theme toggle in the header and toggles theme when clicked", async () => {
    const user = userEvent.setup();
    const handleSignOut = vi.fn();
    const handlePageChange = vi.fn();

    render(
      <ThemeProvider>
        <AdminLayout
          user={mockAdminUser}
          activePage="users"
          onPageChange={handlePageChange}
          onSignOut={handleSignOut}
        >
          <div>Main Content</div>
        </AdminLayout>
      </ThemeProvider>,
    );

    expect(screen.getByText("Admin User")).toBeInTheDocument();
    expect(screen.getByText("ADMIN")).toBeInTheDocument();
    expect(screen.getByText("Main Content")).toBeInTheDocument();

    const toggleBtn = screen.getByRole("button", {
      name: /switch to dark mode/i,
    });
    expect(toggleBtn).toBeInTheDocument();
    expect(document.documentElement.classList.contains("dark")).toBe(false);

    await user.click(toggleBtn);

    expect(document.documentElement.classList.contains("dark")).toBe(true);
    expect(document.documentElement.style.colorScheme).toBe("dark");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("dark");

    const lightToggleBtn = screen.getByRole("button", {
      name: /switch to light mode/i,
    });
    expect(lightToggleBtn).toBeInTheDocument();

    await user.click(lightToggleBtn);

    expect(document.documentElement.classList.contains("dark")).toBe(false);
    expect(document.documentElement.style.colorScheme).toBe("light");
    expect(localStorage.getItem("wallet_admin_theme_mode")).toBe("light");
  });

  it("calls onPageChange when a navigation menu item is clicked", async () => {
    const user = userEvent.setup();
    const handleSignOut = vi.fn();
    const handlePageChange = vi.fn();

    render(
      <ThemeProvider>
        <AdminLayout
          user={mockAdminUser}
          activePage="users"
          onPageChange={handlePageChange}
          onSignOut={handleSignOut}
        >
          <div>Main Content</div>
        </AdminLayout>
      </ThemeProvider>,
    );

    const documentsMenuItem = screen.getByRole("menuitem", {
      name: /documents/i,
    });
    await user.click(documentsMenuItem);

    expect(handlePageChange).toHaveBeenCalledWith("documents");
  });

  it("calls onSignOut when the Sign Out button is clicked", async () => {
    const user = userEvent.setup();
    const handleSignOut = vi.fn();
    const handlePageChange = vi.fn();

    render(
      <ThemeProvider>
        <AdminLayout
          user={mockAdminUser}
          activePage="users"
          onPageChange={handlePageChange}
          onSignOut={handleSignOut}
        >
          <div>Main Content</div>
        </AdminLayout>
      </ThemeProvider>,
    );

    const signOutButton = screen.getByRole("button", { name: /sign out/i });
    await user.click(signOutButton);

    expect(handleSignOut).toHaveBeenCalledTimes(1);
  });
});
