import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { UsersPage } from "./UsersPage";

describe("UsersPage rendering and actions", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("renders users table and opens issue document modal", async () => {
    const user = userEvent.setup();

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url.includes("/api/admin/users")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              items: [
                {
                  id: "u-101",
                  name: "Test Citizen",
                  email: "citizen@test.com",
                  role: "user",
                  createdAt: "2026-03-01T10:00:00.000Z",
                  documentCount: 2,
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

    render(<UsersPage />);

    expect(await screen.findByText("Test Citizen")).toBeInTheDocument();
    expect(screen.getByText("citizen@test.com")).toBeInTheDocument();
    expect(screen.getByText("USER")).toBeInTheDocument();

    const issueButton = screen.getByRole("button", { name: /issue document/i });
    await user.click(issueButton);

    expect(
      await screen.findByText(/Issue Identity Document - Test Citizen/i),
    ).toBeInTheDocument();
  });

  it("triggers search with debounced query parameter", async () => {
    const user = userEvent.setup();

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url.includes("/api/admin/users")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              items: [],
              total: 0,
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

    render(<UsersPage />);

    const searchInput = screen.getByPlaceholderText(
      "Search by name or email...",
    );
    await user.type(searchInput, "Dara");

    await waitFor(
      () => {
        const queryCalls = fetchMock.mock.calls.filter((call) =>
          String(call[0]).includes("q=Dara"),
        );
        expect(queryCalls.length).toBeGreaterThan(0);
      },
      { timeout: 1500 },
    );
  });
});
