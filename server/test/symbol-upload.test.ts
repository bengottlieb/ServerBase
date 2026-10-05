import { describe, expect, it } from 'vitest'
import { z, ZodError } from 'zod'
import { bearerMatches, parseSymbolUpload, symbolUploadHeaders } from '../src/index.js'

// A dSYM upload names its binary in headers; a wrong UUID or vmaddr would attach DWARF to the wrong crash frames. The
// header prefix is the app's, so it is a parameter.
const headers = (prefix: string, over: Record<string, string> = {}) => ({
	[`${prefix}binary-uuid`]: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
	[`${prefix}arch`]: 'arm64',
	[`${prefix}name`]: 'ExampleApp',
	[`${prefix}bundle-id`]: 'com.example.app',
	[`${prefix}text-vmaddr`]: '0x100000000',
	...Object.fromEntries(Object.entries(over).map(([key, value]) => [`${prefix}${key}`, value])),
})

describe('symbol upload headers', () => {
	it('normalises the UUID and vmaddr, under whatever prefix the app uses', () => {
		for (const prefix of ['x-one-', 'x-two-']) {
			expect(parseSymbolUpload(headers(prefix, { 'app-version': '1.2' }), prefix)).toEqual({
				binaryUUID: 'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB',
				arch: 'arm64',
				name: 'ExampleApp',
				bundleID: 'com.example.app',
				appVersion: '1.2',
				appBuild: null,
				textVmaddr: '4294967296',
			})
		}
	})
	it('ignores headers under another prefix', () => {
		expect(() => parseSymbolUpload(headers('x-one-'), 'x-two-')).toThrow()
	})
	it('refuses a bad uuid, architecture, name and out-of-range vmaddr', () => {
		const bad: Record<string, string>[] = [
			{ 'binary-uuid': 'nope' },
			{ arch: 'mips' },
			{ name: '' },
			{ 'text-vmaddr': '0x8000000000000000' },
			{ 'text-vmaddr': '-1' },
			{ 'app-version': 'x'.repeat(41) },
		]
		for (const over of bad) expect(() => parseSymbolUpload(headers('x-one-', over), 'x-one-')).toThrow()
	})
	// A malformed vmaddr must come back as a validation error (a 400), not BigInt's SyntaxError (a 500).
	it('refuses a malformed vmaddr as a validation error', () => {
		for (const vmaddr of ['zz', '0xzz', '']) {
			expect(() => parseSymbolUpload(headers('x-one-', { 'text-vmaddr': vmaddr }), 'x-one-')).toThrow(ZodError)
		}
	})
	// Servers validate these headers through Fastify, which turns the schema into JSON Schema and drops regex flags.
	// Upper-case UUIDs (what dSYM uploads send) and hex must still match there.
	it('accepts upper-case UUIDs and hex once turned into JSON Schema', () => {
		const schema = z.toJSONSchema(symbolUploadHeaders('x-one-')) as { properties: Record<string, { pattern?: string }> }
		const pattern = (name: string) => new RegExp(schema.properties[`x-one-${name}`]!.pattern!)
		expect(pattern('binary-uuid').test('BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB')).toBe(true)
		expect(pattern('text-vmaddr').test('0x1000000AB')).toBe(true)
		expect(pattern('text-vmaddr').test('0X100000000')).toBe(false)
	})
})

describe('bearer token', () => {
	it('matches only the exact token, and never when none is configured', () => {
		expect(bearerMatches('Bearer secret', 'secret')).toBe(true)
		expect(bearerMatches('Bearer secrets', 'secret')).toBe(false)
		expect(bearerMatches('secret', 'secret')).toBe(false)
		expect(bearerMatches(undefined, 'secret')).toBe(false)
		expect(bearerMatches('Bearer ', '')).toBe(false)
		expect(bearerMatches('Bearer undefined', undefined)).toBe(false)
	})
})
