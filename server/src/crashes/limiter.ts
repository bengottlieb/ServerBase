/**
 * At most `max` jobs at once, the rest queued in order: how a server keeps the symbolizer from taking every core.
 * Share one instance wherever the limit should hold (a process, or a service).
 */
export class ConcurrencyLimiter {
	private active = 0
	private readonly waiters: (() => void)[] = []

	constructor(readonly max: number) {}

	async run<T>(work: () => Promise<T>): Promise<T> {
		if (this.active >= this.max) await new Promise<void>((resolve) => this.waiters.push(resolve))
		else this.active++
		try {
			return await work()
		} finally {
			// A finished job hands its slot straight to the next waiter.
			const next = this.waiters.shift()
			if (next) next()
			else this.active--
		}
	}
}
