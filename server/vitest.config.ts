import { defineConfig } from 'vitest/config'

// Pure logic only: no database, no network. A real llvm-symbolizer is never required.
export default defineConfig({
	test: { include: ['test/**/*.test.ts'] },
})
