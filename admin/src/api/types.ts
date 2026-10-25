export type UserRole = "user" | "admin";

export interface User {
  id: string;
  name: string;
  email: string;
  emailVerified: boolean;
  image?: string | null;
  role: UserRole;
  createdAt: string;
  updatedAt: string;
}

export interface SessionData {
  id: string;
  userId: string;
  expiresAt: string;
}

export interface SessionResponse {
  session: SessionData | null;
  user: User | null;
}

export interface SignInResponse {
  token: string;
  user: User;
}

export interface AdminUserListItem {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  createdAt: string;
  documentCount: number;
}

export interface AdminUsersResponse {
  items: AdminUserListItem[];
  total: number;
}

export type DocumentType = "driving_license";

export type DocumentStatus = "issued" | "revoked";

export interface DrivingLicenseData {
  fullName: string;
  dateOfBirth: string;
  address: string;
  nationality: string;
  issuingAuthority: string;
  licenseClasses: string[];
  restrictions: string[];
  issueDate: string;
  expiryDate: string;
}

export interface AdminDocumentListItem {
  id: string;
  userId: string;
  userEmail: string;
  type: DocumentType;
  documentNumber: string;
  status: DocumentStatus;
  issuedAt: string;
  expiresAt: string;
  revokedAt: string | null;
}

export interface AdminDocumentsResponse {
  items: AdminDocumentListItem[];
  total: number;
}

export interface CreateDocumentRequest {
  userId: string;
  type: DocumentType;
  data: DrivingLicenseData;
}

export interface ApiErrorPayload {
  statusCode: number;
  message: string | string[];
  error: string;
}
