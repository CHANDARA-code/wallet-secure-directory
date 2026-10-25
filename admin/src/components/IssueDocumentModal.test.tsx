import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { IssueDocumentModal } from "./IssueDocumentModal";
import type { AdminUserListItem } from "../api/types";

describe("IssueDocumentModal validation", () => {
  const mockUser: AdminUserListItem = {
    id: "user-456",
    name: "Sok Dara",
    email: "sok@example.com",
    role: "user",
    createdAt: "2026-01-01T00:00:00.000Z",
    documentCount: 0,
  };

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("blocks submit when expiry <= issue date and when no license class is chosen", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const handleSuccess = vi.fn();
    const handleClose = vi.fn();

    render(
      <IssueDocumentModal
        open={true}
        user={mockUser}
        onClose={handleClose}
        onSuccess={handleSuccess}
      />,
    );

    const fullNameInput = screen.getByLabelText("Full Name");
    expect(fullNameInput).toHaveValue("Sok Dara");

    const dobInput = screen.getByLabelText("Date of Birth");
    fireEvent.change(dobInput, { target: { value: "1995-04-12" } });
    fireEvent.keyDown(dobInput, { key: "Enter", code: "Enter" });

    const addressInput = screen.getByLabelText("Address");
    await user.type(addressInput, "12 Street 51, Phnom Penh");

    const nationalityInput = screen.getByLabelText("Nationality");
    expect(nationalityInput).toHaveValue("KH");

    const authorityInput = screen.getByLabelText("Issuing Authority");
    expect(authorityInput).toHaveValue(
      "Ministry of Public Works and Transport",
    );

    const issueDateInput = screen.getByLabelText("Issue Date");
    fireEvent.change(issueDateInput, { target: { value: "2026-05-01" } });
    fireEvent.keyDown(issueDateInput, { key: "Enter", code: "Enter" });

    const expiryDateInput = screen.getByLabelText("Expiry Date");
    fireEvent.change(expiryDateInput, { target: { value: "2026-05-01" } });
    fireEvent.keyDown(expiryDateInput, { key: "Enter", code: "Enter" });

    const submitButton = screen.getByRole("button", {
      name: /issue document/i,
    });
    await user.click(submitButton);

    await waitFor(() => {
      expect(
        screen.getByText("Expiry date must be after issue date"),
      ).toBeInTheDocument();
      expect(
        screen.getByText("At least one license class is required"),
      ).toBeInTheDocument();
    });

    expect(fetchMock).not.toHaveBeenCalled();
    expect(handleSuccess).not.toHaveBeenCalled();

    fireEvent.change(expiryDateInput, { target: { value: "2026-04-30" } });
    fireEvent.keyDown(expiryDateInput, { key: "Enter", code: "Enter" });
    await user.click(submitButton);

    await waitFor(() => {
      expect(
        screen.getByText("Expiry date must be after issue date"),
      ).toBeInTheDocument();
    });

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("submits valid form with exact contract payload and ISO dates and calls onSuccess", async () => {
    const user = userEvent.setup();
    const mockCreatedDoc = {
      id: "doc-created-1",
      documentNumber: "DL-0123456789",
      userId: "user-456",
      userEmail: "sok@example.com",
      type: "driving_license",
      status: "issued",
      issuedAt: "2026-05-01T00:00:00.000Z",
      expiresAt: "2031-05-01T00:00:00.000Z",
      revokedAt: null,
    };

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/admin/documents")) {
        return Promise.resolve(
          new Response(JSON.stringify(mockCreatedDoc), {
            status: 201,
            headers: { "Content-Type": "application/json" },
          }),
        );
      }
      return Promise.reject(new Error(`Unexpected fetch: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    const handleSuccess = vi.fn();
    const handleClose = vi.fn();

    render(
      <IssueDocumentModal
        open={true}
        user={mockUser}
        onClose={handleClose}
        onSuccess={handleSuccess}
      />,
    );

    const dobInput = screen.getByLabelText("Date of Birth");
    fireEvent.change(dobInput, { target: { value: "1995-04-12" } });
    fireEvent.keyDown(dobInput, { key: "Enter", code: "Enter" });

    const addressInput = screen.getByLabelText("Address");
    await user.type(addressInput, "12 Street 51, Phnom Penh");

    const licenseClassesInput = screen.getByLabelText("License Classes");
    fireEvent.mouseDown(licenseClassesInput);
    const option = await screen.findByText(
      "B (Passenger Cars <= 9 seats, <= 3.5t)",
    );
    fireEvent.click(option);

    const issueDateInput = screen.getByLabelText("Issue Date");
    fireEvent.change(issueDateInput, { target: { value: "2026-05-01" } });
    fireEvent.keyDown(issueDateInput, { key: "Enter", code: "Enter" });

    const expiryDateInput = screen.getByLabelText("Expiry Date");
    fireEvent.change(expiryDateInput, { target: { value: "2031-05-01" } });
    fireEvent.keyDown(expiryDateInput, { key: "Enter", code: "Enter" });

    const submitButton = screen.getByRole("button", {
      name: /issue document/i,
    });
    await user.click(submitButton);

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/admin/documents",
        expect.objectContaining({
          method: "POST",
          body: JSON.stringify({
            userId: "user-456",
            type: "driving_license",
            data: {
              fullName: "Sok Dara",
              dateOfBirth: "1995-04-12",
              address: "12 Street 51, Phnom Penh",
              nationality: "KH",
              issuingAuthority: "Ministry of Public Works and Transport",
              licenseClasses: ["B"],
              restrictions: [],
              issueDate: "2026-05-01",
              expiryDate: "2031-05-01",
            },
          }),
        }),
      );
    });

    expect(handleSuccess).toHaveBeenCalledWith(mockCreatedDoc);
    expect(await screen.findByText("DL-0123456789")).toBeInTheDocument();
  });

  it("displays server 400 validation error message array against fields", async () => {
    const user = userEvent.setup();

    const fetchMock = vi.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/admin/documents")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              statusCode: 400,
              message: [
                "data.address: Address is invalid",
                "data.dateOfBirth: Date of birth cannot be in the future",
              ],
              error: "Bad Request",
            }),
            {
              status: 400,
              headers: { "Content-Type": "application/json" },
            },
          ),
        );
      }
      return Promise.reject(new Error(`Unexpected fetch: ${url}`));
    });

    vi.stubGlobal("fetch", fetchMock);

    const handleSuccess = vi.fn();
    const handleClose = vi.fn();

    render(
      <IssueDocumentModal
        open={true}
        user={mockUser}
        onClose={handleClose}
        onSuccess={handleSuccess}
      />,
    );

    const dobInput = screen.getByLabelText("Date of Birth");
    fireEvent.change(dobInput, { target: { value: "1995-04-12" } });
    fireEvent.keyDown(dobInput, { key: "Enter", code: "Enter" });

    const addressInput = screen.getByLabelText("Address");
    await user.type(addressInput, "12 Street 51, Phnom Penh");

    const licenseClassesInput = screen.getByLabelText("License Classes");
    fireEvent.mouseDown(licenseClassesInput);
    const option = await screen.findByText(
      "B (Passenger Cars <= 9 seats, <= 3.5t)",
    );
    fireEvent.click(option);

    const issueDateInput = screen.getByLabelText("Issue Date");
    fireEvent.change(issueDateInput, { target: { value: "2026-05-01" } });
    fireEvent.keyDown(issueDateInput, { key: "Enter", code: "Enter" });

    const expiryDateInput = screen.getByLabelText("Expiry Date");
    fireEvent.change(expiryDateInput, { target: { value: "2031-05-01" } });
    fireEvent.keyDown(expiryDateInput, { key: "Enter", code: "Enter" });

    const submitButton = screen.getByRole("button", {
      name: /issue document/i,
    });
    await user.click(submitButton);

    expect(await screen.findByText("Address is invalid")).toBeInTheDocument();
    expect(
      await screen.findByText("Date of birth cannot be in the future"),
    ).toBeInTheDocument();
    expect(handleSuccess).not.toHaveBeenCalled();
  });
});
