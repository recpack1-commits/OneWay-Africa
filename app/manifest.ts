import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "OneWay Africa",
    short_name: "OneWay Africa",
    description:
      "OneWay Africa is a Christian missions organisation advancing the gospel among unreached people groups.",
    start_url: "/",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#1f5a46",
    icons: [
      {
        src: "/icons/oneway-africa-mark.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/oneway-africa-mark-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
    ],
  };
}
