import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DocumentsPage } from "./DocumentsPage";

describe("DocumentsPage revoke flow", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("revoke asks for confirmation before calling the API", async () => {
    const user = userEvent.setup();

    const fetchMock = vi
      .fn()
      .mockImplementation((input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);

        if (
          url.includes("/api/admin/documents") &&
          (!init || init.method === "GET")
        ) {
          return Promise.resolve(
            new Response(
              JSON.stringify({
                items: [
                  {
                    id: "doc-rev-1",
                    userId: "user-789",
                    userEmail: "citizen@example.com",
                    type: "driving_license",
                    documentNumber: "DL-9988776655",
                    status: "issued",
                    issuedAt: "2026-01-15T00:00:00.000Z",
                    expiresAt: "2036-01-14T23:59:59.999Z",
                    revokedAt: null,
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

        if (
          url.includes("/api/admin/documents/doc-rev-1/revoke") &&
          init?.method === "POST"
        ) {
          return Promise.resolve(
            new Response(
              JSON.stringify({
                id: "doc-rev-1",
                userId: "user-789",
                userEmail: "citizen@example.com",
                type: "driving_license",
                documentNumber: "DL-9988776655",
                status: "revoked",
                issuedAt: "2026-01-15T00:00:00.000Z",
                expiresAt: "2036-01-14T23:59:59.999Z",
                revokedAt: "2026-02-01T12:00:00.000Z",
              }),
              {
                status: 200,
                headers: { "Content-Type": "application/json" },
              },
            ),
          );
        }

        return Promise.reject(new Error(`Unexpected call: ${url}`));
      });

    vi.stubGlobal("fetch", fetchMock);

    render(<DocumentsPage />);

    expect(await screen.findByText("DL-9988776655")).toBeInTheDocument();
    expect(screen.getByText("ISSUED")).toBeInTheDocument();

    const revokeButton = screen.getByRole("button", { name: /revoke/i });
    await user.click(revokeButton);

    const confirmationTitle = await screen.findByText(
      "Are you sure you want to revoke this document?",
    );
    expect(confirmationTitle).toBeInTheDocument();

    const revokeCallsBeforeConfirmation = fetchMock.mock.calls.filter((call) =>
      String(call[0]).includes("/revoke"),
    );
    expect(revokeCallsBeforeConfirmation).toHaveLength(0);

    const confirmButton = screen.getByRole("button", { name: /yes, revoke/i });
    await user.click(confirmButton);

    await waitFor(() => {
      const revokeCallsAfterConfirmation = fetchMock.mock.calls.filter((call) =>
        String(call[0]).includes("/revoke"),
      );
      expect(revokeCallsAfterConfirmation).toHaveLength(1);
      expect(revokeCallsAfterConfirmation[0][1]).toEqual(
        expect.objectContaining({
          method: "POST",
        }),
      );
    });
  });

  it("sends userId and resets to page 1 when filtering by user ID", async () => {
    const user = userEvent.setup();

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/admin/documents")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              items: [
                {
                  id: "doc-1",
                  userId: "user-abc",
                  userEmail: "abc@example.com",
                  type: "driving_license",
                  documentNumber: "DL-1111111111",
                  status: "issued",
                  issuedAt: "2026-01-15T00:00:00.000Z",
                  expiresAt: "2036-01-14T23:59:59.999Z",
                  revokedAt: null,
                },
              ],
              total: 25,
            }),
            {
              status: 200,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      }
      return Promise.reject(new Error(`Unexpected call: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<DocumentsPage />);

    expect(await screen.findByText("DL-1111111111")).toBeInTheDocument();

    const page2Button = screen.getByRole("listitem", { name: "2" });
    await user.click(page2Button);

    await waitFor(() => {
      const callsWithOffset10 = fetchMock.mock.calls.filter((call) =>
        String(call[0]).includes("offset=10"),
      );
      expect(callsWithOffset10.length).toBeGreaterThan(0);
    });

    const filterInput = screen.getByPlaceholderText("Filter by User ID...");
    await user.type(filterInput, "user-target");

    await waitFor(
      () => {
        const callsWithFilterAndReset = fetchMock.mock.calls.filter((call) => {
          const url = String(call[0]);
          return url.includes("offset=0") && url.includes("userId=user-target");
        });
        expect(callsWithFilterAndReset.length).toBeGreaterThan(0);
      },
      { timeout: 2000 },
    );
  });

  it("shows an error state on API 500 instead of a blank table", async () => {
    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/admin/documents")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              statusCode: 500,
              message: "Internal server error",
              error: "Internal Server Error",
            }),
            {
              status: 500,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      }
      return Promise.reject(new Error(`Unexpected call: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    render(<DocumentsPage />);

    expect(
      await screen.findByText("Failed to Load Documents"),
    ).toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });
});
