import { Button } from "antd";
import { MoonOutlined, SunOutlined } from "@ant-design/icons";
import { useTheme } from "../theme/ThemeProvider";

export function ThemeToggle() {
  const { mode, toggleTheme } = useTheme();
  const nextMode = mode === "dark" ? "light" : "dark";
  const label = `Switch to ${nextMode} mode`;

  return (
    <Button
      type="text"
      aria-label={label}
      icon={mode === "dark" ? <SunOutlined /> : <MoonOutlined />}
      onClick={toggleTheme}
    />
  );
}

export default ThemeToggle;
