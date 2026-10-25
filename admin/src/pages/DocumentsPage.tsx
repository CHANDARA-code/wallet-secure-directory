import { useCallback, useEffect, useState } from "react";
import {
  Button,
  Card,
  Input,
  Popconfirm,
  Result,
  Space,
  Table,
  Tag,
  Typography,
  message,
} from "antd";
import type { TableColumnsType, TablePaginationConfig } from "antd";
import { SearchOutlined, StopOutlined } from "@ant-design/icons";
import dayjs from "dayjs";
import { getDocuments, revokeDocument } from "../api/documents";
import { ApiError } from "../api/client";
import type { AdminDocumentListItem } from "../api/types";

const DEFAULT_PAGE_SIZE = 10;

export function DocumentsPage() {
  const [documents, setDocuments] = useState<AdminDocumentListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [hasError, setHasError] = useState(false);
  const [limit, setLimit] = useState(DEFAULT_PAGE_SIZE);
  const [offset, setOffset] = useState(0);
  const [userIdFilter, setUserIdFilter] = useState("");
  const [debouncedUserId, setDebouncedUserId] = useState("");
  const [revokingId, setRevokingId] = useState<string | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedUserId(userIdFilter);
      setOffset(0);
    }, 300);

    return () => clearTimeout(timer);
  }, [userIdFilter]);

  const fetchDocuments = useCallback(async () => {
    setLoading(true);
    setHasError(false);
    try {
      const response = await getDocuments({
        limit,
        offset,
        userId: debouncedUserId,
      });
      setDocuments(response.items);
      setTotal(response.total);
    } catch {
      setHasError(true);
      message.error("Failed to load documents");
    } finally {
      setLoading(false);
    }
  }, [limit, offset, debouncedUserId]);

  useEffect(() => {
    fetchDocuments();
  }, [fetchDocuments]);

  const handleTableChange = (pagination: TablePaginationConfig) => {
    const newPage = pagination.current || 1;
    const newPageSize = pagination.pageSize || DEFAULT_PAGE_SIZE;
    setLimit(newPageSize);
    setOffset((newPage - 1) * newPageSize);
  };

  const handleRevokeConfirm = async (id: string) => {
    setRevokingId(id);
    try {
      await revokeDocument(id);
      message.success("Document revoked successfully");
      fetchDocuments();
    } catch (error) {
      if (error instanceof ApiError) {
        message.error(error.messages.join(" "));
      } else {
        message.error("Failed to revoke document");
      }
    } finally {
      setRevokingId(null);
    }
  };

  const columns: TableColumnsType<AdminDocumentListItem> = [
    {
      title: "Document Number",
      dataIndex: "documentNumber",
      key: "documentNumber",
      render: (text: string) => <Typography.Text code>{text}</Typography.Text>,
    },
    {
      title: "User Email",
      dataIndex: "userEmail",
      key: "userEmail",
    },
    {
      title: "Type",
      dataIndex: "type",
      key: "type",
      render: (type: string) => (
        <Tag>{type.replace("_", " ").toUpperCase()}</Tag>
      ),
    },
    {
      title: "Status",
      dataIndex: "status",
      key: "status",
      render: (status: string) => (
        <Tag color={status === "issued" ? "success" : "error"}>
          {status.toUpperCase()}
        </Tag>
      ),
    },
    {
      title: "Issued At",
      dataIndex: "issuedAt",
      key: "issuedAt",
      render: (date: string) => (date ? dayjs(date).format("YYYY-MM-DD") : "-"),
    },
    {
      title: "Expires At",
      dataIndex: "expiresAt",
      key: "expiresAt",
      render: (date: string) => (date ? dayjs(date).format("YYYY-MM-DD") : "-"),
    },
    {
      title: "Revoked At",
      dataIndex: "revokedAt",
      key: "revokedAt",
      render: (date: string | null) =>
        date ? dayjs(date).format("YYYY-MM-DD HH:mm") : "-",
    },
    {
      title: "Actions",
      key: "actions",
      render: (_, record) => {
        const isRevoked = record.status === "revoked";
        const isPending = revokingId === record.id;

        return (
          <Popconfirm
            title="Are you sure you want to revoke this document?"
            okText="Yes, revoke"
            cancelText="Cancel"
            okButtonProps={{ danger: true, loading: isPending }}
            disabled={isRevoked}
            onConfirm={() => handleRevokeConfirm(record.id)}
          >
            <Button
              danger
              size="small"
              icon={<StopOutlined />}
              disabled={isRevoked}
              loading={isPending}
            >
              {isRevoked ? "Revoked" : "Revoke"}
            </Button>
          </Popconfirm>
        );
      },
    },
  ];

  return (
    <div>
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          flexWrap: "wrap",
          gap: 16,
          marginBottom: 16,
        }}
      >
        <div>
          <Typography.Title level={3} style={{ margin: 0 }}>
            Documents
          </Typography.Title>
          <Typography.Text type="secondary">
            View issued identity documents and perform revocations
          </Typography.Text>
        </div>

        <Space>
          <Input
            placeholder="Filter by User ID..."
            prefix={<SearchOutlined />}
            value={userIdFilter}
            onChange={(e) => setUserIdFilter(e.target.value)}
            allowClear
            style={{ width: 280 }}
          />
        </Space>
      </div>

      <Card styles={{ body: { padding: hasError ? 24 : 0 } }}>
        {hasError ? (
          <Result
            status="error"
            title="Failed to Load Documents"
            subTitle="An error occurred while fetching the document list. Please try again."
            extra={
              <Button type="primary" onClick={fetchDocuments}>
                Retry
              </Button>
            }
          />
        ) : (
          <Table<AdminDocumentListItem>
            columns={columns}
            dataSource={documents}
            rowKey="id"
            loading={loading}
            pagination={{
              current: Math.floor(offset / limit) + 1,
              pageSize: limit,
              total,
              showSizeChanger: true,
              pageSizeOptions: ["10", "20", "50"],
              showTotal: (totalCount) => `Total ${totalCount} documents`,
            }}
            onChange={handleTableChange}
            scroll={{ x: 900 }}
          />
        )}
      </Card>
    </div>
  );
}

export default DocumentsPage;
