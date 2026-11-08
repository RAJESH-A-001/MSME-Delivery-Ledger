import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
// Tailwind CSS v4 uses a Vite plugin — no tailwind.config.js required
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
})
