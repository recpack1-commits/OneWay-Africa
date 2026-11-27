import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  experimental: {
    serverActions: {
      bodySizeLimit: "6mb",
      ...(process.env.NODE_ENV === "development"
        ? {
            allowedOrigins: [
              "localhost:3000",
              "127.0.0.1:3000",
              "*.app.github.dev",
              "*.github.dev",
            ],
          }
        : {}),
    },
  },
};

export default nextConfig;
