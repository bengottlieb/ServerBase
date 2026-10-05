/**
 * A per-key allowance over a fixed window, in memory: `hit` spends one
 * and returns null, or returns the seconds until the window resets. Bounded, so a flood of keys can't grow it.
 */
export class AttemptWindow {
	private windows = new Map<string, { start: number; count: number }>()
	private sweptAt = 0

	constructor(
		private readonly limit: number,
		private readonly windowMs: number,
		private readonly maxKeys = 10_000,
	) {}

	hit(key: string, now = Date.now()): number | null {
		this.prune(now)
		const window = this.windows.get(key)
		if (!window || now - window.start >= this.windowMs) {
			this.windows.delete(key)
			this.windows.set(key, { start: now, count: 1 })
			return null
		}
		if (window.count >= this.limit) return Math.max(1, Math.ceil((window.start + this.windowMs - now) / 1000))
		window.count++
		return null
	}

	private prune(now: number) {
		if (now - this.sweptAt >= this.windowMs) {
			this.sweptAt = now
			for (const [key, window] of this.windows) if (now - window.start >= this.windowMs) this.windows.delete(key)
		}
		let overflow = this.windows.size - this.maxKeys
		for (const key of this.windows.keys()) {
			if (overflow-- <= 0) break
			this.windows.delete(key)
		}
	}
}
