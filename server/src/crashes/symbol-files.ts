import { createHash, randomUUID } from 'node:crypto'
import { mkdir, rename, stat, unlink, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { promisify } from 'node:util'
import { gunzip } from 'node:zlib'

const unzip = promisify(gunzip)
export const MAX_DWARF_BYTES = 512 * 1024 * 1024

/** Expands an uploaded (gzipped) dSYM's DWARF, refusing one that would expand past 512 MiB. */
export async function unpackSymbols(data: Buffer): Promise<Buffer> {
	return unzip(data, { maxOutputLength: MAX_DWARF_BYTES })
}

/**
 * The expanded DWARF on disk for llvm-symbolizer, written once per upload. Paths are keyed by content, so a replacement
 * upload never reuses stale DWARF, and written atomically, so concurrent jobs never read a half-written file.
 */
export async function symbolFile(directory: string, uuid: string, compressed: Buffer): Promise<string> {
	if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(uuid)) throw new Error('invalid symbol UUID')
	const digest = createHash('sha256').update(compressed).digest('hex')
	await mkdir(directory, { recursive: true, mode: 0o700 })
	const path = join(directory, `${uuid.toUpperCase()}-${digest}`)
	try {
		const existing = await stat(path)
		if (existing.isFile() && existing.size > 0) return path
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error
	}
	const bytes = await unpackSymbols(compressed)
	if (!bytes.length) throw new Error('empty DWARF')
	const temporary = `${path}.${randomUUID()}.tmp`
	try {
		await writeFile(temporary, bytes, { flag: 'wx', mode: 0o600 })
		await rename(temporary, path)
	} finally {
		await unlink(temporary).catch(() => {})
	}
	return path
}
