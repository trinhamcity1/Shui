import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";

const queryClient = new QueryClient();

/**
 * Scaffold-only placeholder (Phase 6.1). Auth/role gating (6.2), the real
 * routes, and everything past that land in later sub-phases — this proves
 * the stack (React, Tailwind reading Shui's own palette, routing, React
 * Query) is wired correctly before building on top of it.
 */
function DashboardHome() {
  return (
    <div className="min-h-screen bg-canvas p-8">
      <div className="mx-auto max-w-2xl rounded-[var(--radius-card)] border border-border-subtle bg-surface p-8 shadow-sm">
        <p className="text-sm font-medium text-accent">Shui</p>
        <h1 className="mt-1 text-2xl font-bold text-text-primary">Creator Dashboard</h1>
        <p className="mt-2 text-text-secondary">
          Scaffold is up: Vite, React, Tailwind reading Shui&apos;s own palette, routing, and
          React Query. Auth and the real screens come next.
        </p>
        <div className="mt-6 flex gap-3">
          <span className="rounded-full bg-surface-subtle px-3 py-1 text-xs font-semibold text-text-secondary">
            surfaceSubtle
          </span>
          <span className="rounded-full border border-border px-3 py-1 text-xs font-semibold text-text-primary">
            border
          </span>
          <span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold text-text-on-accent">
            accent
          </span>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<DashboardHome />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
