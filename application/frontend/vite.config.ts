import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The API origin is injected at build time by CI (VITE_API_BASE_URL) so the same
// bundle works against API Gateway, an ALB, or a local uvicorn process.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: "http://localhost:8000",
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: "dist",
    sourcemap: false,
    chunkSizeWarningLimit: 900,
  },
});
