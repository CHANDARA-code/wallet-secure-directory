import { useState } from "react";
import { Alert, Button, Card, Form, Input, Typography, theme } from "antd";
import { LockOutlined, UserOutlined } from "@ant-design/icons";
import { signIn } from "../api/auth";
import { ApiError } from "../api/client";
import type { User } from "../api/types";
import { ThemeToggle } from "../components/ThemeToggle";

interface LoginPageProps {
  onLoginSuccess: (user: User) => void;
}

interface LoginFormValues {
  email: string;
  password: string;
}

export function LoginPage({ onLoginSuccess }: LoginPageProps) {
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const { token } = theme.useToken();

  const handleSubmit = async (values: LoginFormValues) => {
    setLoading(true);
    setErrorMessage(null);

    try {
      const response = await signIn({
        email: values.email.trim(),
        password: values.password,
      });
      onLoginSuccess(response.user);
    } catch (error) {
      if (error instanceof ApiError) {
        setErrorMessage(error.messages.join(" "));
      } else if (error instanceof Error) {
        setErrorMessage(error.message);
      } else {
        setErrorMessage("Authentication failed");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: token.colorBgBase,
        padding: 16,
        position: "relative",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 16,
          right: 16,
        }}
      >
        <ThemeToggle />
      </div>

      <Card
        style={{
          width: "100%",
          maxWidth: 400,
        }}
      >
        <div style={{ textAlign: "center", marginBottom: 24 }}>
          <Typography.Title level={3} style={{ margin: 0 }}>
            Admin Portal
          </Typography.Title>
          <Typography.Text type="secondary">
            Sign in with administrative credentials
          </Typography.Text>
        </div>

        {errorMessage && (
          <Alert
            message="Sign In Failed"
            description={errorMessage}
            type="error"
            showIcon
            closable
            onClose={() => setErrorMessage(null)}
            style={{ marginBottom: 16 }}
          />
        )}

        <Form<LoginFormValues>
          layout="vertical"
          name="loginForm"
          onFinish={handleSubmit}
          requiredMark={false}
        >
          <Form.Item
            label="Email"
            name="email"
            rules={[
              { required: true, message: "Please enter your email" },
              { type: "email", message: "Please enter a valid email address" },
            ]}
          >
            <Input
              prefix={<UserOutlined />}
              placeholder="admin@example.com"
              autoComplete="email"
              size="large"
            />
          </Form.Item>

          <Form.Item
            label="Password"
            name="password"
            rules={[{ required: true, message: "Please enter your password" }]}
          >
            <Input.Password
              prefix={<LockOutlined />}
              placeholder="Password"
              autoComplete="current-password"
              size="large"
            />
          </Form.Item>

          <Form.Item style={{ marginBottom: 0, marginTop: 16 }}>
            <Button
              type="primary"
              htmlType="submit"
              size="large"
              block
              loading={loading}
            >
              Sign In
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}

export default LoginPage;
