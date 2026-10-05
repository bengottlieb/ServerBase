import { matchesAppBinary, type DiagnosticFrame } from './stacks.js'
import type { SymbolLocation, SymbolizerRunner } from './symbolizer-runner.js'
import { demangle } from './symbolizer-runner.js'

// The part of symbolication that never touches a database: turning a report's frames into resolved ones through a
// `SymbolizerRunner`, and deciding the outcome. Each server loads the stored dSYM and records the result itself.

export interface ResolvedFrame extends DiagnosticFrame {
	function: string | null
	file: string | null
	line: number | null
	/** Innermost first: the inlined frames, then the function they were inlined into. */
	inlines: SymbolLocation[]
}

/** `done`, `missing_symbols` (the app's own binary has no dSYM yet) or `unavailable` (the symbolizer failed). */
export type SymbolicationState = 'done' | 'missing_symbols' | 'unavailable'

/** Frames not yet resolved, ready for `resolveFrameGroup`. */
export function unresolvedFrames(frames: DiagnosticFrame[]): ResolvedFrame[] {
	return frames.map((frame) => ({ ...frame, function: null, file: null, line: null, inlines: [] }))
}

/** The frames split by the binary they are in, in order of first appearance. */
export function groupByBinary<T extends DiagnosticFrame>(frames: T[]): Map<string, T[]> {
	const groups = new Map<string, T[]>()
	for (const frame of frames) groups.set(frame.binaryUUID, [...(groups.get(frame.binaryUUID) ?? []), frame])
	return groups
}

/** Whether any frame of the group is in the app's own binary: only then does a missing dSYM matter. */
export function groupIsOwn(group: DiagnosticFrame[], ownName: string): boolean {
	return group.some((frame) => matchesAppBinary(frame.binaryName, ownName))
}

/** The address llvm-symbolizer is asked about: the binary's text vmaddr plus the frame's offset into it. */
export function frameAddress(vmaddr: bigint, frame: DiagnosticFrame): bigint {
	return vmaddr + BigInt(frame.offset)
}

export interface FrameGroupSource {
	/** The expanded DWARF on disk (see `symbolFile`). */
	objectPath: string
	arch: string
	/** The binary's `__TEXT` vmaddr, as recorded when its dSYM was uploaded. */
	vmaddr: bigint
}

/**
 * Resolves one binary's frames in place through the runner, demangling Swift names. Returns true when one of the app's
 * own frames came back unresolved, which makes the report `unavailable` rather than `done`.
 */
export async function resolveFrameGroup(
	group: ResolvedFrame[],
	source: FrameGroupSource,
	runner: SymbolizerRunner,
	ownName: string,
): Promise<boolean> {
	const addresses = [...new Set(group.map((frame) => `0x${frameAddress(source.vmaddr, frame).toString(16)}`))]
	const results = await runner(source.objectPath, source.arch, addresses)
	const byAddress = new Map(results.map((result) => [result.address, result.locations]))
	let failed = false
	for (const frame of group) {
		const locations = byAddress.get(frameAddress(source.vmaddr, frame).toString()) ?? []
		frame.inlines = await Promise.all(
			locations.map(async (location) => ({ ...location, function: await demangle(location.function) })),
		)
		const first = frame.inlines[0]
		if (first) Object.assign(frame, { function: first.function, file: first.file, line: first.line })
		else if (matchesAppBinary(frame.binaryName, ownName)) failed = true
	}
	return failed
}

/** A report's title: the innermost resolved function in the app's own binary. */
export function crashTitle(frames: ResolvedFrame[], ownName: string): string | null {
	return frames.find((frame) => matchesAppBinary(frame.binaryName, ownName) && frame.function)?.function ?? null
}

/** A missing dSYM outranks a failed run. */
export function symbolicationState(outcome: { missing: boolean; failed: boolean }): SymbolicationState {
	return outcome.missing ? 'missing_symbols' : outcome.failed ? 'unavailable' : 'done'
}

/** The symbolizer executable isn't installed (its spawn failed with ENOENT), as opposed to failing on a report. */
export function isSymbolizerMissing(error: unknown): boolean {
	return (error as NodeJS.ErrnoException | undefined)?.code === 'ENOENT'
}
