import { apiClient } from "./client";
import type { AdminUsersResponse } from "./types";

export interface GetUsersParams {
  limit?: number;
  offset?: number;
  q?: string;
}

export async function getUsers(
  params: GetUsersParams = {},
): Promise<AdminUsersResponse> {
  const query = new URLSearchParams();

  if (typeof params.limit === "number") {
    query.set("limit", String(params.limit));
  }
  if (typeof params.offset === "number") {
    query.set("offset", String(params.offset));
  }
  if (params.q && params.q.trim().length > 0) {
    query.set("q", params.q.trim());
  }

  const queryString = query.toString();
  const path = queryString
    ? `/api/admin/users?${queryString}`
    : "/api/admin/users";

  return apiClient<AdminUsersResponse>(path, {
    method: "GET",
  });
}
