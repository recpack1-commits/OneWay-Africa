import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "JFC & BiblePlus Inventory Platform",
    short_name: "JFC & BiblePlus",
    description: "Quick access to JFC outreach data and BiblePlus audio Bible inventory.",
    start_url: "/",
    display: "standalone",
    background_color: "#F7FAF5",
    theme_color: "#800D1D",
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
