import { useState, type ReactNode } from "react";
import { Button, Layout, Menu, Space, Tag, Typography, theme } from "antd";
import type { MenuProps } from "antd";
import {
  FileTextOutlined,
  LeftOutlined,
  LogoutOutlined,
  RightOutlined,
  UserOutlined,
} from "@ant-design/icons";
import type { User } from "../api/types";
import { ThemeToggle } from "./ThemeToggle";

const { Header, Content, Sider } = Layout;

interface AdminLayoutProps {
  user: User;
  activePage: "users" | "documents";
  onPageChange: (page: "users" | "documents") => void;
  onSignOut: () => void;
  children: ReactNode;
}

export function AdminLayout({
  user,
  activePage,
  onPageChange,
  onSignOut,
  children,
}: AdminLayoutProps) {
  const [collapsed, setCollapsed] = useState(false);
  const { token } = theme.useToken();

  const menuItems: MenuProps["items"] = [
    {
      key: "users",
      icon: <UserOutlined />,
      label: "Users",
    },
    {
      key: "documents",
      icon: <FileTextOutlined />,
      label: "Documents",
    },
  ];

  return (
    <Layout style={{ minHeight: "100vh", background: token.colorBgBase }}>
      <Header
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "0 16px",
          height: 72,
          borderBottom: `1px solid ${token.colorBorderSecondary}`,
          background: token.colorBgContainer,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <Typography.Title level={4} style={{ margin: 0 }}>
            Wallet Admin
          </Typography.Title>
        </div>

        <Space size="middle" wrap>
          <ThemeToggle />
          <div
            style={{
              textAlign: "right",
              display: "flex",
              alignItems: "center",
              gap: 8,
            }}
          >
            <Typography.Text>{user.name}</Typography.Text>
            <Tag color="gold">{user.role.toUpperCase()}</Tag>
          </div>

          <Button type="text" icon={<LogoutOutlined />} onClick={onSignOut}>
            Sign Out
          </Button>
        </Space>
      </Header>

      <Layout style={{ background: "transparent" }}>
        <Sider
          collapsible
          collapsed={collapsed}
          onCollapse={setCollapsed}
          trigger={null}
          breakpoint="md"
          collapsedWidth={80}
          width={200}
          theme="light"
          style={{
            background: token.colorBgContainer,
            borderRight: `1px solid ${token.colorBorderSecondary}`,
          }}
        >
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              height: "100%",
              justifyContent: "space-between",
            }}
          >
            <div style={{ flex: 1, overflowY: "auto", overflowX: "hidden" }}>
              <Menu
                mode="inline"
                selectedKeys={[activePage]}
                onClick={({ key }) =>
                  onPageChange(key as "users" | "documents")
                }
                style={{
                  height: "100%",
                  background: "transparent",
                  borderRight: 0,
                }}
                items={menuItems}
              />
            </div>
            <button
              type="button"
              className="ant-layout-sider-trigger"
              aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
              onClick={() => setCollapsed(!collapsed)}
              style={{
                width: "100%",
                height: 48,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                background: token.colorBgContainer,
                color: token.colorTextSecondary,
                border: "none",
                borderTop: `1px solid ${token.colorBorderSecondary}`,
                cursor: "pointer",
                padding: 0,
                transition: "all 0.2s",
              }}
            >
              {collapsed ? <RightOutlined /> : <LeftOutlined />}
            </button>
          </div>
        </Sider>

        <Layout style={{ padding: "16px", background: "transparent" }}>
          <Content
            style={{
              padding: 16,
              margin: 0,
              minHeight: 280,
              background: "transparent",
            }}
          >
            {children}
          </Content>
        </Layout>
      </Layout>
    </Layout>
  );
}

export default AdminLayout;
