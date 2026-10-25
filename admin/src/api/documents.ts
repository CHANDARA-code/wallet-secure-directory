import { apiClient } from "./client";
import type {
  AdminDocumentListItem,
  AdminDocumentsResponse,
  CreateDocumentRequest,
} from "./types";

export interface GetDocumentsParams {
  limit?: number;
  offset?: number;
  userId?: string;
}

export async function getDocuments(
  params: GetDocumentsParams = {},
): Promise<AdminDocumentsResponse> {
  const query = new URLSearchParams();

  if (typeof params.limit === "number") {
    query.set("limit", String(params.limit));
  }
  if (typeof params.offset === "number") {
    query.set("offset", String(params.offset));
  }
  if (params.userId && params.userId.trim().length > 0) {
    query.set("userId", params.userId.trim());
  }

  const queryString = query.toString();
  const path = queryString
    ? `/api/admin/documents?${queryString}`
    : "/api/admin/documents";

  return apiClient<AdminDocumentsResponse>(path, {
    method: "GET",
  });
}

export async function issueDocument(
  payload: CreateDocumentRequest,
): Promise<AdminDocumentListItem> {
  return apiClient<AdminDocumentListItem>("/api/admin/documents", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

export async function revokeDocument(
  id: string,
): Promise<AdminDocumentListItem> {
  return apiClient<AdminDocumentListItem>(
    `/api/admin/documents/${encodeURIComponent(id)}/revoke`,
    {
      method: "POST",
      body: JSON.stringify({}),
    },
  );
}
