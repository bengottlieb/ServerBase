import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { gzipSync } from 'node:zlib'
import { describe, expect, it } from 'vitest'
import { demangle, llvmSymbolizer, parseSymbolizerOutput, symbolFile } from '../src/index.js'

// llvm-symbolizer is driven over stdin and read as a JSON stream; a misparse silently mislabels a crash.
// The fake symbolizer is a script, so no real LLVM is needed.
const result = (address: string, name = 'function { nested } text') => ({
	Address: address,
	Symbol: [{ FunctionName: name, FileName: '/src/test.swift', Line: 12 }],
})

describe('symbolizer protocol', () => {
	it('parses pretty-printed adjacent objects without splitting quoted braces', () => {
		const parsed = parseSymbolizerOutput(
			JSON.stringify(result('0x1000'), null, 2) + '\n' + JSON.stringify(result('0x1001', 'a } { b')),
		)
		expect(parsed.map((x) => x.address)).toEqual(['4096', '4097'])
		expect(parsed[1]!.locations[0]!.function).toBe('a } { b')
	})
	it('distinguishes missing locations and malformed output', () => {
		expect(parseSymbolizerOutput(JSON.stringify(result('0x1000', '??')))[0]!.locations).toEqual([])
		for (const output of ['garbage', '{', '{"Address":"no address","Symbol":[]}', '{"Address":"0x1"}'])
			expect(() => parseSymbolizerOutput(output)).toThrow()
	})
	it('demangles a real Swift symbol through WASM', async () => {
		expect(await demangle('$sSi1soiyS2i_SitFZ')).toBe('static Swift.Int.- infix(Swift.Int, Swift.Int) -> Swift.Int')
		expect(await demangle('_$sSi1soiyS2i_SitFZ')).toBe('static Swift.Int.- infix(Swift.Int, Swift.Int) -> Swift.Int')
		expect(await demangle('main')).toBe('main')
	})
	it('invokes a process without shell expansion and sends addresses on stdin', async () => {
		const directory = await mkdtemp(join(tmpdir(), 'server-base-symbolizer-runner-'))
		try {
			const binary = join(directory, 'fake-symbolizer')
			const capture = join(directory, 'arguments.json')
			await writeFile(
				binary,
				`#!${process.execPath}\nconst fs=require('fs');const text=fs.readFileSync(0,'utf8');fs.writeFileSync(${JSON.stringify(capture)},JSON.stringify({args:process.argv.slice(2),input:text}));for(const Address of text.trim().split('\\n')) console.log(JSON.stringify({Address,Symbol:[{FunctionName:'main',FileName:'',Line:0}]}));`,
				{ mode: 0o700 },
			)
			const object = join(directory, 'object $(must-not-run) with spaces')
			const output = await llvmSymbolizer(binary)(object, 'arm64', ['0x100000001', '0x100000002'])
			expect(output.map((x) => x.address)).toEqual(['4294967297', '4294967298'])
			const recorded = JSON.parse(await readFile(capture, 'utf8'))
			expect(recorded.args).toContain(`--obj=${object}`)
			expect(recorded.input).toBe('0x100000001\n0x100000002\n')
		} finally {
			await rm(directory, { recursive: true, force: true })
		}
	})
	it('keeps concurrent cache writes atomic and replacement uploads distinct', async () => {
		const directory = await mkdtemp(join(tmpdir(), 'server-base-symbol-cache-'))
		const uuid = 'BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB'
		try {
			const compressed = gzipSync('first DWARF')
			const paths = await Promise.all([
				symbolFile(directory, uuid, compressed),
				symbolFile(directory, uuid, compressed),
			])
			expect(paths[0]).toBe(paths[1])
			expect(await readFile(paths[0]!, 'utf8')).toBe('first DWARF')
			const replacement = await symbolFile(directory, uuid, gzipSync('replacement DWARF'))
			expect(replacement).not.toBe(paths[0])
			expect(await readFile(replacement, 'utf8')).toBe('replacement DWARF')
			await expect(symbolFile(directory, '../escape', compressed)).rejects.toThrow()
			await expect(symbolFile(directory, uuid, Buffer.from('not gzip'))).rejects.toThrow()
		} finally {
			await rm(directory, { recursive: true, force: true })
		}
	})
})
