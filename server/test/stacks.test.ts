import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { appBinaryName, attributedFrames, matchesAppBinary, signatureFor } from '../src/index.js'

// Grouping is what makes a crash list readable: the same crash must land in one group whatever ASLR or the encoding
// did, and different crashes must not share one.
const fixture = (name = 'crash') =>
	JSON.parse(readFileSync(new URL(`./fixtures/metrickit/${name}.json`, import.meta.url), 'utf8'))
const frame = (offset: unknown = 1) => ({
	binaryUUID: 'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB',
	binaryName: 'ExampleApp',
	offsetIntoBinaryTextSegment: offset,
})
const payload = (frames: unknown[]) => ({ callStackTree: { callStacks: [{ callStackRootFrames: frames }] } })

describe('MetricKit attributed stacks', () => {
	it('chooses the attributed thread and walks nested frames top-down', () => {
		expect(attributedFrames(fixture(), 'crash').map((f) => f.offset)).toEqual(['4096', '8192'])
	})
	it('groups ASLR changes and UUID case/offset encodings identically', () => {
		const one = fixture()
		const two = fixture()
		const root = two.callStackTree.callStacks[1].callStackRootFrames[0]
		root.address = 9999999
		root.binaryUUID = root.binaryUUID.toLowerCase()
		root.offsetIntoBinaryTextSegment = '0x1000'
		expect(signatureFor(one, 'ExampleApp', 'crash')).toBe(signatureFor(two, 'ExampleApp', 'crash'))
		root.offsetIntoBinaryTextSegment = 4097
		expect(signatureFor(one, 'ExampleApp', 'crash')).not.toBe(signatureFor(two, 'ExampleApp', 'crash'))
	})
	it('uses eight app frames and ignores system frames when app frames exist', () => {
		const frames = Array.from({ length: 9 }, (_, i) => frame(i))
		const expected = signatureFor(payload(frames), 'ExampleApp', 'crash')
		frames[8]!.offsetIntoBinaryTextSegment = 42
		frames.unshift({ ...frame(42), binaryName: 'UIKit' })
		expect(signatureFor(payload(frames), 'ExampleApp', 'crash')).toBe(expected)
		frames[2]!.offsetIntoBinaryTextSegment = 64
		expect(signatureFor(payload(frames), 'ExampleApp', 'crash')).not.toBe(expected)
	})
	it('treats the Xcode debug dylib as app code rather than a system fallback', () => {
		const own = { ...frame(16), binaryName: 'ExampleApp.debug.dylib' }
		const system = { ...frame(32), binaryName: 'UIKit' }
		expect(signatureFor(payload([system, own]), 'ExampleApp', 'crash')).toBe(
			signatureFor(payload([own]), 'ExampleApp', 'crash'),
		)
	})
	it('falls back to the first stack and system frames', () => {
		expect(signatureFor(payload([{ ...frame(), binaryName: 'UIKit' }]), 'ExampleApp', 'crash')).toMatch(
			/^[0-9a-f]{16}$/,
		)
	})
	it('keeps unsigned 64-bit offsets precise and rejects rounded JSON numbers', () => {
		expect(attributedFrames(payload([frame('18446744073709551615')]), 'crash')[0]!.offset).toBe('18446744073709551615')
		for (const value of [Number.MAX_SAFE_INTEGER + 1, -1, '18446744073709551616', '-1', '1.5', 'garbage'])
			expect(() => attributedFrames(payload([frame(value)]), 'crash')).toThrow('no usable frames')
	})
	it('rejects malformed, empty, too broad and too deep trees without recursion', () => {
		for (const value of [
			{},
			payload([]),
			payload([null]),
			payload([{ ...frame(), subFrames: {} }]),
			payload(Array.from({ length: 10001 }, () => frame())),
		])
			expect(() => attributedFrames(value, 'crash')).toThrow()
		let nested: unknown = frame()
		for (let i = 0; i < 258; i++) nested = { ...frame(), subFrames: [nested] }
		expect(() => attributedFrames(payload([nested]), 'crash')).toThrow('exceeds limits')
	})
})

describe('MetricKit hang stacks', () => {
	const offsets = (value: Record<string, unknown>) =>
		attributedFrames(value, 'hang').map((f) => `${f.binaryName}+${f.offset}`)
	it('reads the main thread, not the attributed one, along its most-sampled path, innermost first', () => {
		expect(offsets(fixture('hang'))).toEqual([
			'libsystem_kernel.dylib+20',
			'ExampleApp+400',
			'UIKitCore+200',
			'ExampleApp+100',
			'dyld+1',
		])
	})
	it('falls back to the attributed thread when no thread was entered from dyld', () => {
		const hang = fixture('hang')
		hang.callStackTree.callStacks.shift()
		expect(offsets(hang)).toEqual(['BoardServices+6', 'libsystem_pthread.dylib+5'])
	})
	it('leaves main out of the signature: a hang is grouped by where it hung', () => {
		const one = fixture('hang')
		const two = fixture('hang')
		two.callStackTree.callStacks[0].callStackRootFrames[0].subFrames[0].offsetIntoBinaryTextSegment = 104
		expect(signatureFor(one, 'ExampleApp', 'hang')).toBe(signatureFor(two, 'ExampleApp', 'hang'))
		two.callStackTree.callStacks[0].callStackRootFrames[0].subFrames[0].subFrames[0].subFrames[1].offsetIntoBinaryTextSegment = 404
		expect(signatureFor(one, 'ExampleApp', 'hang')).not.toBe(signatureFor(two, 'ExampleApp', 'hang'))
	})
	it('still refuses a malformed tree', () => {
		const hang = fixture('hang')
		hang.callStackTree.callStacks[0].callStackRootFrames[0].subFrames = {}
		expect(() => attributedFrames(hang, 'hang')).toThrow()
	})
})

describe('app binary names', () => {
	// Each server owns its bundle id → binary map; the library hard-codes none.
	it('looks the binary up in the map the server passes, and an unknown bundle id names itself', () => {
		const binaries = { 'com.example.app': 'ExampleApp' }
		expect(appBinaryName(binaries, 'com.example.app')).toBe('ExampleApp')
		expect(appBinaryName(binaries, 'com.example.other')).toBe('com.example.other')
		expect(appBinaryName({}, 'com.example.app')).toBe('com.example.app')
	})
	it('matches the launcher and its Xcode debug dylib, nothing else', () => {
		expect(matchesAppBinary('ExampleApp', 'ExampleApp')).toBe(true)
		expect(matchesAppBinary('ExampleApp.debug.dylib', 'ExampleApp')).toBe(true)
		expect(matchesAppBinary('UIKit', 'ExampleApp')).toBe(false)
	})
})
