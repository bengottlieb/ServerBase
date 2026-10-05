import { describe, expect, it } from 'vitest'
import { AttemptWindow } from '../src/index.js'

// The window is a rate limiter on caller-chosen keys (IPs, accounts): it must answer 'wait N seconds', reset on time,
// and never let a flood of keys grow it without bound.
describe('AttemptWindow', () => {
	it('allows the limit, then says how many seconds remain until the window resets', () => {
		const window = new AttemptWindow(2, 60_000)
		expect(window.hit('a', 0)).toBeNull()
		expect(window.hit('a', 1000)).toBeNull()
		expect(window.hit('a', 10_000)).toBe(50)
		expect(window.hit('a', 59_999)).toBe(1)
	})
	it('keeps keys apart and starts a fresh allowance when the window passes', () => {
		const window = new AttemptWindow(1, 1000)
		expect(window.hit('a', 0)).toBeNull()
		expect(window.hit('b', 0)).toBeNull()
		expect(window.hit('a', 500)).not.toBeNull()
		expect(window.hit('a', 1000)).toBeNull()
	})
	it('forgets the oldest keys beyond maxKeys instead of growing', () => {
		const window = new AttemptWindow(1, 60_000, 2)
		for (const key of ['a', 'b', 'c']) window.hit(key, 0)
		// `a` was evicted, so it gets a fresh allowance; `c` is still counted.
		expect(window.hit('a', 1)).toBeNull()
		expect(window.hit('c', 1)).not.toBeNull()
	})
})
