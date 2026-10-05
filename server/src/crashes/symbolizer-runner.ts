import { execFile } from 'node:child_process'
import initializeDemangler from 'swift-demangle-wasm'

export interface SymbolLocation {
	function: string
	file: string | null
	line: number | null
}
export interface SymbolResult {
	/** Decimal. */
	address: string
	/** Innermost first: the inlined frames, then the function they were inlined into. */
	locations: SymbolLocation[]
}
export type SymbolizerRunner = (objectPath: string, arch: string, addresses: string[]) => Promise<SymbolResult[]>

let demangler: ReturnType<typeof initializeDemangler> | undefined

/** A Swift symbol made readable (in WebAssembly, no toolchain needed); anything else is returned as it is. */
export async function demangle(name: string): Promise<string> {
	if (!/^_?\$s/.test(name)) return name
	return (await (demangler ??= initializeDemangler()))(name)
}

/** LLVM emits a sequence of JSON objects for stdin, possibly pretty-printed. */
export function parseSymbolizerOutput(output: string): SymbolResult[] {
	const values: unknown[] = []
	let start = -1
	let depth = 0
	let quoted = false
	let escaped = false
	for (let i = 0; i < output.length; i++) {
		const char = output[i]!
		if (start < 0) {
			if (/\s/.test(char)) continue
			if (char !== '{') throw new Error('invalid symbolizer JSON sequence')
			start = i
		}
		if (quoted) {
			if (escaped) escaped = false
			else if (char === '\\') escaped = true
			else if (char === '"') quoted = false
		} else if (char === '"') quoted = true
		else if (char === '{') depth++
		else if (char === '}' && --depth === 0) {
			values.push(JSON.parse(output.slice(start, i + 1)))
			start = -1
		}
	}
	if (start >= 0) throw new Error('incomplete symbolizer JSON')
	return values.map((value) => {
		const item = value as {
			Address?: unknown
			Symbol?: Array<{ FunctionName?: unknown; FileName?: unknown; Line?: unknown }>
		}
		if (typeof item.Address !== 'string' || !/^0x[0-9a-f]+$/i.test(item.Address) || !Array.isArray(item.Symbol))
			throw new Error('invalid symbolizer result')
		return {
			address: BigInt(item.Address).toString(),
			locations: item.Symbol.flatMap((symbol) => {
				if (typeof symbol.FunctionName !== 'string' || symbol.FunctionName === '??' || !symbol.FunctionName) return []
				const file = typeof symbol.FileName === 'string' && symbol.FileName !== '??' ? symbol.FileName || null : null
				const line =
					typeof symbol.Line === 'number' && Number.isSafeInteger(symbol.Line) && symbol.Line > 0 ? symbol.Line : null
				return [{ function: symbol.FunctionName, file, line }]
			}),
		}
	})
}

/** Runs `llvm-symbolizer` (no shell) with the addresses on stdin, for one object file and architecture. */
export function llvmSymbolizer(path: string): SymbolizerRunner {
	return (objectPath, arch, addresses) =>
		new Promise((resolve, reject) => {
			const child = execFile(
				path,
				[`--obj=${objectPath}`, `--default-arch=${arch}`, '--output-style=JSON', '--inlines'],
				{
					timeout: 20000,
					killSignal: 'SIGKILL',
					maxBuffer: 32 * 1024 * 1024,
					env: { ...process.env, LLVM_SYMBOLIZER_OPTS: '', DEBUGINFOD_URLS: '' },
				},
				(error, stdout) => {
					if (error) return reject(error)
					try {
						resolve(parseSymbolizerOutput(stdout))
					} catch (parseError) {
						reject(parseError)
					}
				},
			)
			// execFile's callback owns completion, including EPIPE.
			child.stdin?.on('error', () => {})
			child.stdin?.end(addresses.join('\n') + '\n')
		})
}
