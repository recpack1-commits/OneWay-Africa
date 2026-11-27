import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "JFC & BiblePlus Inventory Platform | OneWay Africa",
    template: "%s | JFC & BiblePlus Inventory Platform",
  },
  description:
    "Quick access to JFC outreach data and BiblePlus audio Bible inventory for OneWay Africa.",
  applicationName: "JFC & BiblePlus Inventory Platform",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: "/icons/oneway-africa-mark.png",
    apple: "/icons/oneway-africa-mark.png",
  },
};

export const viewport: Viewport = {
  themeColor: "#800D1D",
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
