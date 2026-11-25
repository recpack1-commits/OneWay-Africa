import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "OneWay Africa Ministry Platform",
    short_name: "OneWay Africa",
    description: "Secure ministry management for OneWay Africa and BiblePlus.",
    start_url: "/",
    display: "standalone",
    background_color: "#f6f5ef",
    theme_color: "#1f5a46",
    icons: [
      {
        src: "/icons/icon-192.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
      {
        src: "/icons/icon-512.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any",
      },
    ],
  };
}
