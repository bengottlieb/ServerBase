import { describe, expect, it } from 'vitest'
import {
	ConcurrencyLimiter,
	crashTitle,
	groupByBinary,
	groupIsOwn,
	isSymbolizerMissing,
	resolveFrameGroup,
	symbolicationState,
	unresolvedFrames,
	type DiagnosticFrame,
	type SymbolizerRunner,
} from '../src/index.js'

// The database-free half of symbolication: which addresses are asked for, how answers land on frames, and what the
// outcome means. A wrong address or a swallowed failure mislabels a crash or hides a missing dSYM.
const UUID = 'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB'
const frame = (offset: string, binaryName = 'ExampleApp'): DiagnosticFrame => ({ binaryUUID: UUID, binaryName, offset })
const source = { objectPath: '/tmp/dwarf', arch: 'arm64', vmaddr: 0x100000000n }

describe('frame resolution', () => {
	it('asks for vmaddr + offset once per distinct address, and fills frames from the answers', async () => {
		let asked: string[] = []
		const runner: SymbolizerRunner = async (_path, _arch, addresses) => {
			asked = addresses
			return [{ address: '4294967297', locations: [{ function: 'main', file: '/a.swift', line: 7 }] }]
		}
		const frames = unresolvedFrames([frame('1'), frame('1'), frame('2')])
		const failed = await resolveFrameGroup(frames, source, runner, 'ExampleApp')
		expect(asked).toEqual(['0x100000001', '0x100000002'])
		expect(frames[0]).toMatchObject({ function: 'main', file: '/a.swift', line: 7 })
		expect(frames[0]!.inlines).toHaveLength(1)
		expect(frames[2]!.function).toBeNull()
		expect(failed).toBe(true)
	})
	it('demangles Swift names', async () => {
		const runner: SymbolizerRunner = async () => [
			{ address: '4294967297', locations: [{ function: '$sSi1soiyS2i_SitFZ', file: null, line: null }] },
		]
		const frames = unresolvedFrames([frame('1')])
		await resolveFrameGroup(frames, source, runner, 'ExampleApp')
		expect(frames[0]!.function).toBe('static Swift.Int.- infix(Swift.Int, Swift.Int) -> Swift.Int')
	})
	it('only counts an unresolved frame as a failure when it is in the app', async () => {
		const frames = unresolvedFrames([frame('1', 'UIKit')])
		expect(await resolveFrameGroup(frames, source, async () => [], 'ExampleApp')).toBe(false)
	})
	it('lets a runner error reach the caller, which decides the report is unavailable', async () => {
		const runner: SymbolizerRunner = async () => Promise.reject(Object.assign(new Error('x'), { code: 'ENOENT' }))
		const error = await resolveFrameGroup(unresolvedFrames([frame('1')]), source, runner, 'ExampleApp').catch((e) => e)
		expect(isSymbolizerMissing(error)).toBe(true)
		expect(isSymbolizerMissing(new Error('boom'))).toBe(false)
	})
})

describe('outcome', () => {
	it('groups by binary and tells the app from system groups', () => {
		const groups = groupByBinary([frame('1'), { ...frame('2', 'UIKit'), binaryUUID: 'C' }, frame('3')])
		expect([...groups.keys()]).toEqual([UUID, 'C'])
		expect(groupIsOwn(groups.get(UUID)!, 'ExampleApp')).toBe(true)
		expect(groupIsOwn(groups.get('C')!, 'ExampleApp')).toBe(false)
	})
	it('titles a report by its innermost resolved app function', () => {
		const frames = unresolvedFrames([frame('1', 'UIKit'), frame('2'), frame('3')])
		frames[0]!.function = 'systemThing'
		frames[2]!.function = 'appThing'
		expect(crashTitle(frames, 'ExampleApp')).toBe('appThing')
		expect(crashTitle(unresolvedFrames([frame('1')]), 'ExampleApp')).toBeNull()
	})
	it('reports a missing dSYM ahead of a failed run', () => {
		expect(symbolicationState({ missing: true, failed: true })).toBe('missing_symbols')
		expect(symbolicationState({ missing: false, failed: true })).toBe('unavailable')
		expect(symbolicationState({ missing: false, failed: false })).toBe('done')
	})
})

describe('ConcurrencyLimiter', () => {
	it('never runs more than max at once, and runs every job', async () => {
		const limiter = new ConcurrencyLimiter(2)
		let running = 0
		let peak = 0
		const job = async () => {
			peak = Math.max(peak, ++running)
			await new Promise((resolve) => setTimeout(resolve, 5))
			running--
			return 1
		}
		const results = await Promise.all(Array.from({ length: 6 }, () => limiter.run(job)))
		expect(results).toHaveLength(6)
		expect(peak).toBe(2)
	})
	it('frees its slot when a job throws', async () => {
		const limiter = new ConcurrencyLimiter(1)
		await expect(limiter.run(() => Promise.reject(new Error('x')))).rejects.toThrow('x')
		expect(await limiter.run(async () => 'ok')).toBe('ok')
	})
})
