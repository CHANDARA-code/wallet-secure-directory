import { useEffect, useState } from "react";
import {
  Alert,
  Button,
  DatePicker,
  Form,
  Input,
  Modal,
  Result,
  Select,
  Space,
  theme,
} from "antd";
import type { Dayjs } from "dayjs";
import { issueDocument } from "../api/documents";
import { ApiError } from "../api/client";
import type {
  AdminDocumentListItem,
  AdminUserListItem,
  CreateDocumentRequest,
} from "../api/types";

interface IssueDocumentModalProps {
  open: boolean;
  user: AdminUserListItem | null;
  onClose: () => void;
  onSuccess: (document: AdminDocumentListItem) => void;
}

interface IssueFormValues {
  fullName: string;
  dateOfBirth: Dayjs;
  address: string;
  nationality: string;
  issuingAuthority: string;
  licenseClasses: string[];
  restrictions?: string[];
  issueDate: Dayjs;
  expiryDate: Dayjs;
}

const LICENSE_CLASS_OPTIONS = [
  { label: "A (Motorcycles > 125cc)", value: "A" },
  { label: "A1 (Light Motorcycles <= 125cc)", value: "A1" },
  { label: "B (Passenger Cars <= 9 seats, <= 3.5t)", value: "B" },
  { label: "C (Heavy Trucks > 3.5t)", value: "C" },
  { label: "C1 (Medium Trucks 3.5t - 7.5t)", value: "C1" },
  { label: "D (Buses > 16 seats)", value: "D" },
  { label: "D1 (Small Buses 9 - 16 seats)", value: "D1" },
  { label: "E (Vehicles with Heavy Trailer)", value: "E" },
];

const RESTRICTION_OPTIONS = [
  { label: "Corrective Lenses (01)", value: "CORRECTIVE_LENSES" },
  { label: "Automatic Transmission (78)", value: "AUTOMATIC_TRANSMISSION" },
  { label: "Hearing Aid", value: "HEARING_AID" },
  { label: "Daylight Only", value: "DAYLIGHT_ONLY" },
];

export function IssueDocumentModal({
  open,
  user,
  onClose,
  onSuccess,
}: IssueDocumentModalProps) {
  const [form] = Form.useForm<IssueFormValues>();
  const [loading, setLoading] = useState(false);
  const [serverErrors, setServerErrors] = useState<string[] | null>(null);
  const [issuedDocument, setIssuedDocument] =
    useState<AdminDocumentListItem | null>(null);
  const { token } = theme.useToken();

  useEffect(() => {
    if (open && user) {
      setServerErrors(null);
      setIssuedDocument(null);
      form.resetFields();
      form.setFieldsValue({
        fullName: user.name,
        nationality: "KH",
        issuingAuthority: "Ministry of Public Works and Transport",
        licenseClasses: [],
        restrictions: [],
      });
    }
  }, [open, user, form]);

  const handleFinish = async (values: IssueFormValues) => {
    if (!user) {
      return;
    }

    setLoading(true);
    setServerErrors(null);

    const payload: CreateDocumentRequest = {
      userId: user.id,
      type: "driving_license",
      data: {
        fullName: values.fullName.trim(),
        dateOfBirth: values.dateOfBirth.format("YYYY-MM-DD"),
        address: values.address.trim(),
        nationality: values.nationality.trim(),
        issuingAuthority: values.issuingAuthority.trim(),
        licenseClasses: values.licenseClasses,
        restrictions: values.restrictions || [],
        issueDate: values.issueDate.format("YYYY-MM-DD"),
        expiryDate: values.expiryDate.format("YYYY-MM-DD"),
      },
    };

    try {
      const created = await issueDocument(payload);
      setIssuedDocument(created);
      onSuccess(created);
    } catch (error) {
      if (error instanceof ApiError) {
        setServerErrors(error.messages);
        const knownFields: (keyof IssueFormValues)[] = [
          "fullName",
          "dateOfBirth",
          "address",
          "nationality",
          "issuingAuthority",
          "licenseClasses",
          "restrictions",
          "issueDate",
          "expiryDate",
        ];
        const errorMap = new Map<keyof IssueFormValues, string[]>();
        for (const msg of error.messages) {
          const match = msg.match(/^(?:data\.)?([a-zA-Z0-9_]+):\s*(.*)$/);
          if (
            match &&
            knownFields.includes(match[1] as keyof IssueFormValues)
          ) {
            const fieldName = match[1] as keyof IssueFormValues;
            const errorText = match[2] || msg;
            const current = errorMap.get(fieldName) || [];
            errorMap.set(fieldName, [...current, errorText]);
            continue;
          }
          for (const field of knownFields) {
            if (msg.toLowerCase().includes(field.toLowerCase())) {
              const current = errorMap.get(field) || [];
              errorMap.set(field, [...current, msg]);
              break;
            }
          }
        }
        if (errorMap.size > 0) {
          const fieldErrors = Array.from(errorMap.entries()).map(
            ([name, errors]) => ({ name, errors }),
          );
          form.setFields(fieldErrors);
        }
      } else if (error instanceof Error) {
        setServerErrors([error.message]);
      } else {
        setServerErrors(["Failed to issue document"]);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleModalClose = () => {
    setServerErrors(null);
    setIssuedDocument(null);
    form.resetFields();
    onClose();
  };

  return (
    <Modal
      open={open}
      title={
        issuedDocument
          ? "Document Issued"
          : `Issue Identity Document - ${user?.name || ""}`
      }
      onCancel={handleModalClose}
      footer={null}
      destroyOnHidden
      width={680}
    >
      {issuedDocument ? (
        <Result
          status="success"
          title="Document Issued Successfully"
          subTitle={
            <div style={{ marginTop: 8 }}>
              <div>Document Number:</div>
              <strong style={{ fontSize: 18, color: token.colorPrimary }}>
                {issuedDocument.documentNumber}
              </strong>
            </div>
          }
          extra={[
            <Button type="primary" key="close" onClick={handleModalClose}>
              Done
            </Button>,
          ]}
        />
      ) : (
        <Form<IssueFormValues>
          form={form}
          layout="vertical"
          name="issueDocumentForm"
          onFinish={handleFinish}
        >
          {serverErrors && serverErrors.length > 0 && (
            <Alert
              message="Validation Error"
              description={
                <ul style={{ margin: 0, paddingLeft: 18 }}>
                  {serverErrors.map((message, index) => (
                    <li key={index}>{message}</li>
                  ))}
                </ul>
              }
              type="error"
              showIcon
              style={{ marginBottom: 16 }}
            />
          )}

          <Form.Item
            label="Full Name"
            name="fullName"
            rules={[{ required: true, message: "Full name is required" }]}
          >
            <Input placeholder="Sok Dara" />
          </Form.Item>

          <Space
            orientation="horizontal"
            size="middle"
            style={{ display: "flex", width: "100%" }}
          >
            <Form.Item
              label="Date of Birth"
              name="dateOfBirth"
              style={{ flex: 1 }}
              rules={[{ required: true, message: "Date of birth is required" }]}
            >
              <DatePicker style={{ width: "100%" }} format="YYYY-MM-DD" />
            </Form.Item>

            <Form.Item
              label="Nationality"
              name="nationality"
              style={{ flex: 1 }}
              rules={[{ required: true, message: "Nationality is required" }]}
            >
              <Input placeholder="KH" maxLength={10} />
            </Form.Item>
          </Space>

          <Form.Item
            label="Address"
            name="address"
            rules={[{ required: true, message: "Address is required" }]}
          >
            <Input.TextArea rows={2} placeholder="12 Street 51, Phnom Penh" />
          </Form.Item>

          <Form.Item
            label="Issuing Authority"
            name="issuingAuthority"
            rules={[
              { required: true, message: "Issuing authority is required" },
            ]}
          >
            <Input placeholder="Ministry of Public Works and Transport" />
          </Form.Item>

          <Form.Item
            label="License Classes"
            name="licenseClasses"
            rules={[
              {
                validator: async (_, value: string[]) => {
                  if (!value || !Array.isArray(value) || value.length === 0) {
                    throw new Error("At least one license class is required");
                  }
                },
              },
            ]}
          >
            <Select
              mode="tags"
              placeholder="Select or enter license classes (e.g. B, C1)"
              options={LICENSE_CLASS_OPTIONS}
            />
          </Form.Item>

          <Form.Item label="Restrictions" name="restrictions">
            <Select
              mode="tags"
              placeholder="Optional restrictions (e.g. CORRECTIVE_LENSES)"
              options={RESTRICTION_OPTIONS}
            />
          </Form.Item>

          <Space
            orientation="horizontal"
            size="middle"
            style={{ display: "flex", width: "100%" }}
          >
            <Form.Item
              label="Issue Date"
              name="issueDate"
              style={{ flex: 1 }}
              rules={[{ required: true, message: "Issue date is required" }]}
            >
              <DatePicker
                style={{ width: "100%" }}
                format="YYYY-MM-DD"
                onChange={() => {
                  if (form.getFieldValue("expiryDate")) {
                    form.validateFields(["expiryDate"]);
                  }
                }}
              />
            </Form.Item>

            <Form.Item
              label="Expiry Date"
              name="expiryDate"
              dependencies={["issueDate"]}
              style={{ flex: 1 }}
              rules={[
                {
                  validator: async (_, value: Dayjs | null) => {
                    if (!value) {
                      throw new Error("Expiry date is required");
                    }
                    const issueDate = form.getFieldValue(
                      "issueDate",
                    ) as Dayjs | null;
                    if (issueDate) {
                      const isBeforeOrSame =
                        value.isBefore(issueDate, "day") ||
                        value.isSame(issueDate, "day");
                      if (isBeforeOrSame) {
                        throw new Error("Expiry date must be after issue date");
                      }
                    }
                  },
                },
              ]}
            >
              <DatePicker style={{ width: "100%" }} format="YYYY-MM-DD" />
            </Form.Item>
          </Space>

          <div
            style={{
              display: "flex",
              justifyContent: "flex-end",
              gap: 8,
              marginTop: 16,
            }}
          >
            <Button onClick={handleModalClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="primary" htmlType="submit" loading={loading}>
              Issue Document
            </Button>
          </div>
        </Form>
      )}
    </Modal>
  );
}

export default IssueDocumentModal;
