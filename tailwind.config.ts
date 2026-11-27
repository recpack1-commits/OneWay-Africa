import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#2d201c",
        forest: "#800d1d",
        leaf: "#832927",
        sand: "#f6f5ef",
        sun: "#f0bf67",
      },
      boxShadow: {
        card: "0 24px 70px -38px rgba(45, 32, 28, 0.35)",
      },
    },
  },
  plugins: [require("@tailwindcss/forms")],
};

export default config;
