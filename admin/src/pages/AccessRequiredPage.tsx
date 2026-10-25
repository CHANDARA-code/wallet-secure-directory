import { useState } from "react";
import { Button, Card, Result, theme } from "antd";
import { LogoutOutlined } from "@ant-design/icons";
import { signOut } from "../api/auth";
import { ThemeToggle } from "../components/ThemeToggle";

interface AccessRequiredPageProps {
  onSignedOut: () => void;
}

export function AccessRequiredPage({ onSignedOut }: AccessRequiredPageProps) {
  const [loading, setLoading] = useState(false);
  const { token } = theme.useToken();

  const handleSignOut = async () => {
    setLoading(true);
    try {
      await signOut();
    } finally {
      setLoading(false);
      onSignedOut();
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
          maxWidth: 520,
          width: "100%",
        }}
      >
        <Result
          status="403"
          title="Admin access required"
          subTitle="Your account does not have administrator privileges. Please sign in with an administrator account."
          extra={
            <Button
              type="primary"
              icon={<LogoutOutlined />}
              onClick={handleSignOut}
              loading={loading}
              size="large"
            >
              Sign Out
            </Button>
          }
        />
      </Card>
    </div>
  );
}

export default AccessRequiredPage;
