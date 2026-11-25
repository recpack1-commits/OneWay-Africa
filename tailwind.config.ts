import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#18332d",
        forest: "#1f5a46",
        leaf: "#3d8060",
        sand: "#f6f5ef",
        sun: "#f0bf67",
      },
      boxShadow: {
        card: "0 24px 70px -38px rgba(24, 51, 45, 0.35)",
      },
    },
  },
  plugins: [require("@tailwindcss/forms")],
};

export default config;
