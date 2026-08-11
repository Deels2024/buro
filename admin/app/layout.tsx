import type { Metadata } from "next";
import "./globals.css";
import "./integration.css";
import "./comfort.css";

export const metadata: Metadata = {
  title: "Бюро находок — Админка",
  description: "Операционный центр единой федеральной сети поиска и возврата вещей.",
  other: {
    "codex-preview": "development",
  },
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru">
      <body>{children}</body>
    </html>
  );
}
