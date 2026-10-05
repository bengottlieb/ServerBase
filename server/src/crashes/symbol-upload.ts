import { z } from 'zod'

// The headers of a dSYM upload: one binary's identity, sent beside its gzipped DWARF. The header prefix belongs to the
// app (`x-<app>-`), so it is a parameter.

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i
export const SYMBOL_ARCHITECTURES = ['arm64', 'arm64e', 'x86_64', 'x86_64h'] as const
/** The largest __TEXT vmaddr that still fits a signed 64-bit column. */
const MAX_VMADDR = 0x7fffffffffffffffn

/** The validated upload, normalised: the UUID upper-cased and the vmaddr a decimal string. */
export interface SymbolUpload {
	binaryUUID: string
	arch: (typeof SYMBOL_ARCHITECTURES)[number]
	name: string
	bundleID: string
	appVersion: string | null
	appBuild: string | null
	/** Decimal. */
	textVmaddr: string
}

/** Zod schema for the upload headers under `prefix` (e.g. `x-myapp-`); lower-case names, as Node delivers them. */
export function symbolUploadHeaders(prefix: string) {
	return z.object({
		[`${prefix}binary-uuid`]: z.string().regex(UUID),
		[`${prefix}arch`]: z.enum(SYMBOL_ARCHITECTURES),
		[`${prefix}name`]: z.string().min(1).max(200),
		[`${prefix}bundle-id`]: z.string().min(1).max(200),
		[`${prefix}app-version`]: z.string().max(40).optional(),
		[`${prefix}app-build`]: z.string().max(40).optional(),
		[`${prefix}text-vmaddr`]: z
			.string()
			.regex(/^(?:\d{1,19}|0x[0-9a-f]{1,16})$/i)
			.refine((value) => BigInt(value) <= MAX_VMADDR, 'vmaddr out of range'),
	})
}

/** Validates request headers against `symbolUploadHeaders(prefix)`; throws a ZodError when they don't fit. */
export function parseSymbolUpload(headers: Record<string, unknown>, prefix: string): SymbolUpload {
	const parsed = symbolUploadHeaders(prefix).parse(headers) as Record<string, string | undefined>
	const field = (name: string) => parsed[`${prefix}${name}`]
	return {
		binaryUUID: field('binary-uuid')!.toUpperCase(),
		arch: field('arch') as SymbolUpload['arch'],
		name: field('name')!,
		bundleID: field('bundle-id')!,
		appVersion: field('app-version') ?? null,
		appBuild: field('app-build') ?? null,
		textVmaddr: BigInt(field('text-vmaddr')!).toString(),
	}
}
