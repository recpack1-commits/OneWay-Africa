import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "OneWay Africa",
    template: "%s | OneWay Africa",
  },
  description:
    "OneWay Africa is a Christian missions organisation advancing the gospel among unreached people groups.",
  applicationName: "OneWay Africa",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: "/icons/oneway-africa-mark.png",
    apple: "/icons/oneway-africa-mark.png",
  },
};

export const viewport: Viewport = {
  themeColor: "#1f5a46",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
