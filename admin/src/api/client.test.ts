import { beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError, apiClient, setUnauthorizedListener } from "./client";

describe("apiClient", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    setUnauthorizedListener(null);
  });

  it("sends credentials include and parses json response", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await apiClient<{ success: boolean }>("/api/test");

    expect(result).toEqual({ success: true });
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/test",
      expect.objectContaining({
        credentials: "include",
      }),
    );
  });

  it("notifies unauthorized listener on 401 for authenticated endpoints", async () => {
    const listener = vi.fn();
    setUnauthorizedListener(listener);

    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          statusCode: 401,
          message: "Unauthorized",
          error: "Unauthorized",
        }),
        {
          status: 401,
          headers: { "Content-Type": "application/json" },
        },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(apiClient("/api/admin/users")).rejects.toThrow(ApiError);
    expect(listener).toHaveBeenCalledTimes(1);
  });

  it("normalizes error response with array of messages", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          statusCode: 400,
          message: [
            "fullName is required",
            "expiryDate must be after issueDate",
          ],
          error: "Bad Request",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    try {
      await apiClient("/api/admin/documents", {
        method: "POST",
        body: JSON.stringify({}),
      });
      expect.fail("Expected apiClient to throw ApiError");
    } catch (error) {
      expect(error).toBeInstanceOf(ApiError);
      const apiError = error as ApiError;
      expect(apiError.statusCode).toBe(400);
      expect(apiError.errorName).toBe("Bad Request");
      expect(apiError.messages).toEqual([
        "fullName is required",
        "expiryDate must be after issueDate",
      ]);
    }
  });
});
