import { useCallback, useEffect, useState } from "react";
import {
  Button,
  Card,
  Input,
  Space,
  Table,
  Tag,
  Typography,
  message,
} from "antd";
import type { TableColumnsType, TablePaginationConfig } from "antd";
import { PlusOutlined, SearchOutlined } from "@ant-design/icons";
import dayjs from "dayjs";
import { getUsers } from "../api/users";
import type { AdminUserListItem } from "../api/types";
import { IssueDocumentModal } from "../components/IssueDocumentModal";

const DEFAULT_PAGE_SIZE = 10;

export function UsersPage() {
  const [users, setUsers] = useState<AdminUserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [limit, setLimit] = useState(DEFAULT_PAGE_SIZE);
  const [offset, setOffset] = useState(0);
  const [searchQuery, setSearchQuery] = useState("");
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const [selectedUserForIssue, setSelectedUserForIssue] =
    useState<AdminUserListItem | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedQuery(searchQuery);
      setOffset(0);
    }, 300);

    return () => clearTimeout(timer);
  }, [searchQuery]);

  const fetchUsers = useCallback(async () => {
    setLoading(true);
    try {
      const response = await getUsers({
        limit,
        offset,
        q: debouncedQuery,
      });
      setUsers(response.items);
      setTotal(response.total);
    } catch {
      message.error("Failed to load users");
    } finally {
      setLoading(false);
    }
  }, [limit, offset, debouncedQuery]);

  useEffect(() => {
    fetchUsers();
  }, [fetchUsers]);

  const handleTableChange = (pagination: TablePaginationConfig) => {
    const newPage = pagination.current || 1;
    const newPageSize = pagination.pageSize || DEFAULT_PAGE_SIZE;
    setLimit(newPageSize);
    setOffset((newPage - 1) * newPageSize);
  };

  const handleDocumentIssuedSuccess = () => {
    fetchUsers();
  };

  const columns: TableColumnsType<AdminUserListItem> = [
    {
      title: "Name",
      dataIndex: "name",
      key: "name",
      render: (text: string) => (
        <Typography.Text strong>{text}</Typography.Text>
      ),
    },
    {
      title: "Email",
      dataIndex: "email",
      key: "email",
    },
    {
      title: "Role",
      dataIndex: "role",
      key: "role",
      render: (role: string) => (
        <Tag color={role === "admin" ? "blue" : "default"}>
          {role.toUpperCase()}
        </Tag>
      ),
    },
    {
      title: "Created Date",
      dataIndex: "createdAt",
      key: "createdAt",
      render: (date: string) =>
        date ? dayjs(date).format("YYYY-MM-DD HH:mm") : "-",
    },
    {
      title: "Documents",
      dataIndex: "documentCount",
      key: "documentCount",
      render: (count: number) => (
        <Tag color={count > 0 ? "cyan" : "default"}>{count}</Tag>
      ),
    },
    {
      title: "Actions",
      key: "actions",
      render: (_, record) => (
        <Button
          type="primary"
          size="small"
          icon={<PlusOutlined />}
          onClick={() => setSelectedUserForIssue(record)}
        >
          Issue document
        </Button>
      ),
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
            Users
          </Typography.Title>
          <Typography.Text type="secondary">
            Manage registered users and issue identity credentials
          </Typography.Text>
        </div>

        <Space>
          <Input
            placeholder="Search by name or email..."
            prefix={<SearchOutlined />}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            allowClear
            style={{ width: 280 }}
          />
        </Space>
      </div>

      <Card styles={{ body: { padding: 0 } }}>
        <Table<AdminUserListItem>
          columns={columns}
          dataSource={users}
          rowKey="id"
          loading={loading}
          pagination={{
            current: Math.floor(offset / limit) + 1,
            pageSize: limit,
            total,
            showSizeChanger: true,
            pageSizeOptions: ["10", "20", "50"],
            showTotal: (totalCount) => `Total ${totalCount} users`,
          }}
          onChange={handleTableChange}
          scroll={{ x: 750 }}
        />
      </Card>

      <IssueDocumentModal
        open={Boolean(selectedUserForIssue)}
        user={selectedUserForIssue}
        onClose={() => setSelectedUserForIssue(null)}
        onSuccess={handleDocumentIssuedSuccess}
      />
    </div>
  );
}

export default UsersPage;
