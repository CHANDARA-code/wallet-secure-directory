import { Suspense, lazy, useEffect, useState } from "react";
import { ConfigProvider, Spin } from "antd";
import { getSession, signOut } from "./api/auth";
import { setUnauthorizedListener } from "./api/client";
import type { User } from "./api/types";
import { AdminLayout } from "./components/AdminLayout";
import { AccessRequiredPage } from "./pages/AccessRequiredPage";
import { LoginPage } from "./pages/LoginPage";
import {
  ThemeProvider,
  darkAntdTheme,
  lightAntdTheme,
  useTheme,
} from "./theme/ThemeProvider";

const UsersPage = lazy(() => import("./pages/UsersPage"));
const DocumentsPage = lazy(() => import("./pages/DocumentsPage"));

export type AuthStatus =
  "checking" | "unauthenticated" | "forbidden" | "authenticated";

function AppContent() {
  const [authStatus, setAuthStatus] = useState<AuthStatus>("checking");
  const [currentUser, setCurrentUser] = useState<User | null>(null);
  const [activePage, setActivePage] = useState<"users" | "documents">("users");

  useEffect(() => {
    setUnauthorizedListener(() => {
      setCurrentUser(null);
      setAuthStatus("unauthenticated");
      setActivePage("users");
    });

    return () => {
      setUnauthorizedListener(null);
    };
  }, []);

  useEffect(() => {
    let isCurrent = true;

    async function checkAuthSession() {
      try {
        const sessionData = await getSession();
        if (!isCurrent) {
          return;
        }

        if (sessionData && sessionData.user) {
          setCurrentUser(sessionData.user);
          if (sessionData.user.role === "admin") {
            setAuthStatus("authenticated");
          } else {
            setAuthStatus("forbidden");
          }
        } else {
          setCurrentUser(null);
          setAuthStatus("unauthenticated");
        }
      } catch {
        if (!isCurrent) {
          return;
        }
        setCurrentUser(null);
        setAuthStatus("unauthenticated");
      }
    }

    checkAuthSession();

    return () => {
      isCurrent = false;
    };
  }, []);

  const handleLoginSuccess = (user: User) => {
    setCurrentUser(user);
    if (user.role === "admin") {
      setAuthStatus("authenticated");
    } else {
      setAuthStatus("forbidden");
    }
  };

  const handleSignOut = async () => {
    try {
      await signOut();
    } finally {
      setCurrentUser(null);
      setAuthStatus("unauthenticated");
      setActivePage("users");
    }
  };

  if (authStatus === "checking") {
    return (
      <div
        style={{
          minHeight: "100vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <Spin size="large" />
      </div>
    );
  }

  if (authStatus === "unauthenticated") {
    return <LoginPage onLoginSuccess={handleLoginSuccess} />;
  }

  if (authStatus === "forbidden") {
    return <AccessRequiredPage onSignedOut={handleSignOut} />;
  }

  if (authStatus === "authenticated" && currentUser) {
    return (
      <AdminLayout
        key={currentUser.id}
        user={currentUser}
        activePage={activePage}
        onPageChange={setActivePage}
        onSignOut={handleSignOut}
      >
        <Suspense
          fallback={
            <div
              style={{
                minHeight: 280,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Spin size="large" />
            </div>
          }
        >
          {activePage === "users" ? (
            <UsersPage key={`users-${currentUser.id}`} />
          ) : (
            <DocumentsPage key={`documents-${currentUser.id}`} />
          )}
        </Suspense>
      </AdminLayout>
    );
  }

  return null;
}

function ConfiguredApp() {
  const { mode } = useTheme();

  return (
    <ConfigProvider theme={mode === "dark" ? darkAntdTheme : lightAntdTheme}>
      <AppContent />
    </ConfigProvider>
  );
}

export function App() {
  return (
    <ThemeProvider>
      <ConfiguredApp />
    </ThemeProvider>
  );
}

export default App;
