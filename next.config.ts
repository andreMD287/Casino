import type { NextConfig } from "next";

// cacheComponents queda desactivado a propósito: casi todas las páginas dependen
// de la sesión (cookie), así que el renderizado dinámico clásico es más simple.
const nextConfig: NextConfig = {
  serverExternalPackages: ["pg"],
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
