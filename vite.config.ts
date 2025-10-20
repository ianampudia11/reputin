import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const backendPort = env.PORT || '9000';
  const isProduction = mode === 'production';

  return {
  plugins: [
    react(),
  ],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "client", "src"),
      "@shared": path.resolve(import.meta.dirname, "shared"),
      "@assets": path.resolve(import.meta.dirname, "attached_assets"),
    },
  },
  root: path.resolve(import.meta.dirname, "client"),
  build: {
    outDir: path.resolve(import.meta.dirname, "dist/public"),
    emptyOutDir: true,
    sourcemap: false,
    minify: 'terser',
    terserOptions: {
      compress: {
        drop_console: isProduction, // Remove console logs in production
        drop_debugger: true,
        pure_funcs: isProduction ? ['console.log', 'console.info', 'console.debug', 'console.warn'] : [],
      },
      mangle: {
        toplevel: true,
      },
      format: {
        comments: false,
      },
    },
    rollupOptions: {
      output: {
        manualChunks: undefined,
      },
    },
  },
  json: {
    stringify: false,
  },
  server: {
    port: parseInt(backendPort),
    host: true,
    hmr: {
      overlay: false,
      port: parseInt(backendPort) + 1,
    },
    proxy: {
      '/api': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: true,
        secure: false,
      },
      '/public': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: true,
        secure: false,
      },
      '/uploads': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: true,
        secure: false,
      },
      '/email-attachments': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: true,
        secure: false,
      },
      '/media': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: true,
        secure: false,
      },
      '/robots.txt': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: true,
        secure: false,
      },
      '/ws': {
        target: `ws://localhost:${parseInt(backendPort) + 100}`,
        ws: true,
        changeOrigin: true,
      },

      '^/[a-zA-Z0-9-]+$': {
        target: `http://localhost:${parseInt(backendPort) + 100}`,
        changeOrigin: false, // Preserve original host header for subdomain detection
        secure: false,
        bypass: function (req, res, proxyOptions) {
          const host = req.headers.host || '';
          const path = req.url || '';


          const isSubdomain = host.includes('.localhost') && !host.startsWith('localhost:');


          const appRoutes = [
            '/auth', '/login', '/register', '/dashboard', '/admin', '/settings',
            '/profile', '/logout', '/inbox', '/flows', '/contacts', '/calendar',
            '/analytics', '/campaigns', '/pipeline', '/pages', '/users', '/billing',
            '/integrations', '/reports', '/templates', '/webhooks'
          ];
          const isAppRoute = appRoutes.includes(path) || appRoutes.some(route => path.startsWith(route + '/'));

          if (isSubdomain && !isAppRoute) {

            return null;
          } else {

            return '/index.html';
          }
        },
      },
    },
  },
  };
});
