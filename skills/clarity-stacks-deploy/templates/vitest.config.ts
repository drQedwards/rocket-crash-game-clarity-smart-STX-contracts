import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "clarinet",
    pool: "forks",
    poolOptions: {
      forks: { singleFork: true },
    },
    setupFiles: ["./tests/setup.ts"],
  },
});
