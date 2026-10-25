import React, { createContext, useContext, useEffect, useState } from "react";
import { theme as antdTheme, ThemeConfig } from "antd";

export type ThemeMode = "light" | "dark";

interface ThemeContextType {
  mode: ThemeMode;
  toggleTheme: () => void;
  setMode: (mode: ThemeMode) => void;
}

const STORAGE_KEY = "wallet_admin_theme_mode";

const ThemeContext = createContext<ThemeContextType>({
  mode: "light",
  toggleTheme: () => {},
  setMode: () => {},
});

export const useTheme = () => useContext(ThemeContext);

const fontFamily =
  "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";

export const lightAntdTheme: ThemeConfig = {
  token: {
    fontFamily,
    colorBgBase: "#FAF9F5",
    colorBgContainer: "#F4F3EE",
    colorBgElevated: "#ECEAE1",
    colorBorder: "#E3E1D9",
    colorBorderSecondary: "#E3E1D9",
    colorText: "#1F1E1C",
    colorTextSecondary: "#6B6862",
    colorTextTertiary: "#B1ADA1",
    colorPrimary: "#C15F3C",
    colorPrimaryHover: "#A94F30",
    colorSuccess: "#4A7862",
    colorWarning: "#B08838",
    colorError: "#B3492F",
    borderRadius: 10,
  },
  components: {
    Layout: {
      bodyBg: "#FAF9F5",
      headerBg: "#FAF9F5",
      footerBg: "#FAF9F5",
      headerHeight: 72,
      headerPadding: "0 16px",
    },
    Button: {
      controlHeight: 42,
      fontWeight: 600,
      primaryColor: "#FFFFFF",
      colorPrimary: "#C15F3C",
      colorPrimaryHover: "#A94F30",
      colorPrimaryActive: "#8E3F24",
      borderRadius: 8,
    },
    Card: {
      colorBgContainer: "#F4F3EE",
      colorBorderSecondary: "#E3E1D9",
      borderRadiusLG: 12,
      paddingLG: 16,
    },
    Table: {
      colorBgContainer: "#F4F3EE",
      headerBg: "#ECEAE1",
      borderColor: "#E3E1D9",
      headerColor: "#1F1E1C",
      rowHoverBg: "#ECEAE1",
    },
    Tabs: {
      itemColor: "#6B6862",
      itemHoverColor: "#C15F3C",
      itemSelectedColor: "#C15F3C",
      inkBarColor: "#C15F3C",
    },
    Input: {
      colorBgContainer: "#FAF9F5",
      colorBorder: "#E3E1D9",
      colorText: "#1F1E1C",
      hoverBorderColor: "#C15F3C",
      activeBorderColor: "#C15F3C",
    },
    Tag: {
      borderRadiusSM: 6,
    },
    Modal: {
      contentBg: "#F4F3EE",
      headerBg: "#F4F3EE",
    },
    Drawer: {
      colorBgElevated: "#F4F3EE",
    },
  },
};

export const darkAntdTheme: ThemeConfig = {
  algorithm: antdTheme.darkAlgorithm,
  token: {
    fontFamily,
    colorBgBase: "#1A1917",
    colorBgContainer: "#26241F",
    colorBgElevated: "#322F29",
    colorBorder: "#3D3A33",
    colorBorderSecondary: "#3D3A33",
    colorText: "#F4F3EE",
    colorTextSecondary: "#B1ADA1",
    colorTextTertiary: "#7A766D",
    colorPrimary: "#D97B57",
    colorPrimaryHover: "#E68F6D",
    colorSuccess: "#6FA085",
    colorWarning: "#D0A85C",
    colorError: "#D9705A",
    borderRadius: 10,
  },
  components: {
    Layout: {
      bodyBg: "#1A1917",
      headerBg: "#1A1917",
      footerBg: "#1A1917",
      headerHeight: 72,
      headerPadding: "0 16px",
    },
    Button: {
      controlHeight: 42,
      fontWeight: 600,
      primaryColor: "#1A1917",
      colorPrimary: "#D97B57",
      colorPrimaryHover: "#E68F6D",
      colorPrimaryActive: "#C15F3C",
      borderRadius: 8,
    },
    Card: {
      colorBgContainer: "#26241F",
      colorBorderSecondary: "#3D3A33",
      borderRadiusLG: 12,
      paddingLG: 16,
    },
    Table: {
      colorBgContainer: "#26241F",
      headerBg: "#322F29",
      borderColor: "#3D3A33",
      headerColor: "#F4F3EE",
      rowHoverBg: "#322F29",
    },
    Tabs: {
      itemColor: "#B1ADA1",
      itemHoverColor: "#D97B57",
      itemSelectedColor: "#D97B57",
      inkBarColor: "#D97B57",
    },
    Input: {
      colorBgContainer: "#1A1917",
      colorBorder: "#3D3A33",
      colorText: "#F4F3EE",
      hoverBorderColor: "#D97B57",
      activeBorderColor: "#D97B57",
    },
    Tag: {
      borderRadiusSM: 6,
    },
    Modal: {
      contentBg: "#26241F",
      headerBg: "#26241F",
    },
    Drawer: {
      colorBgElevated: "#26241F",
    },
  },
};

function initialMode(): ThemeMode {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved === "dark" || saved === "light") return saved;
  } catch {}
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [mode, setMode] = useState<ThemeMode>(initialMode);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {}
    document.documentElement.classList.toggle("dark", mode === "dark");
    document.documentElement.style.colorScheme = mode;
    document.body.style.background = mode === "dark" ? "#1A1917" : "#FAF9F5";
  }, [mode]);

  const toggleTheme = () => setMode((prev) => (prev === "light" ? "dark" : "light"));

  return (
    <ThemeContext.Provider value={{ mode, toggleTheme, setMode }}>
      {children}
    </ThemeContext.Provider>
  );
};
