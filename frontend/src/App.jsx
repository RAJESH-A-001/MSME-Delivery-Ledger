/**
 * App.jsx — Root application component (Milestone 1 placeholder)
 *
 * This file will be replaced with routing and feature components
 * in subsequent milestones. It currently serves only as a scaffold
 * validation page to confirm Vite + React + Tailwind are wired correctly.
 */

function App() {
  return (
    <div className="min-h-screen bg-gray-950 text-white flex flex-col items-center justify-center gap-6">
      <h1 className="text-4xl font-bold tracking-tight">
        MSME Delivery &amp; Acceptance Ledger
      </h1>
      <p className="text-gray-400 text-lg">
        Milestone 1 — Project scaffolding complete.
      </p>
      <div className="flex gap-4 text-sm text-gray-500">
        <span className="px-3 py-1 rounded-full bg-gray-800">React {/* version injected at runtime */}</span>
        <span className="px-3 py-1 rounded-full bg-gray-800">Vite</span>
        <span className="px-3 py-1 rounded-full bg-gray-800">Tailwind CSS v4</span>
        <span className="px-3 py-1 rounded-full bg-gray-800">React Router v6</span>
        <span className="px-3 py-1 rounded-full bg-gray-800">Ethers.js v6</span>
      </div>
    </div>
  )
}

export default App
