import { createHash } from 'node:crypto'

// Reading a MetricKit call stack tree: the frames a report is about, and the signature reports are grouped by.

export interface DiagnosticFrame {
	binaryUUID: string
	binaryName: string
	/** Decimal integer string: symbolication must not round addresses. */
	offset: string
}

export type ReportKind = 'crash' | 'hang'

/** Bundle id → the app's main binary name. Each server supplies its own map. */
export type AppBinaries = Record<string, string>

const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i

function object(value: unknown): Record<string, unknown> | undefined {
	return value !== null && typeof value === 'object' && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: undefined
}

function offset(value: unknown): string | undefined {
	if (typeof value === 'number') return Number.isSafeInteger(value) && value >= 0 ? String(value) : undefined
	if (typeof value !== 'string' || !/^(?:\d{1,20}|0x[0-9a-fA-F]{1,16})$/.test(value)) return undefined
	const parsed = BigInt(value)
	return parsed <= 0xffffffffffffffffn ? parsed.toString() : undefined
}

function frameOf(frame: Record<string, unknown>): DiagnosticFrame | undefined {
	const uuid = frame.binaryUUID
	const name = frame.binaryName
	const address = offset(frame.offsetIntoBinaryTextSegment)
	return typeof uuid === 'string' &&
		UUID.test(uuid) &&
		typeof name === 'string' &&
		name.length > 0 &&
		name.length <= 256 &&
		address !== undefined
		? { binaryUUID: uuid.toUpperCase(), binaryName: name, offset: address }
		: undefined
}

/** Every frame of one thread's tree, depth first, bounded and iterative even for hostile nesting. */
function walk(stack: Record<string, unknown> | undefined): DiagnosticFrame[] {
	if (!Array.isArray(stack?.callStackRootFrames)) throw new Error('invalid callStackRootFrames')
	const pending = stack.callStackRootFrames
		.slice()
		.reverse()
		.map((value) => ({ value, depth: 0 }))
	const frames: DiagnosticFrame[] = []
	let visited = 0
	while (pending.length) {
		const { value, depth } = pending.pop()!
		if (++visited > 10000 || depth > 256) throw new Error('callStackTree exceeds limits')
		const frame = object(value)
		if (!frame) throw new Error('invalid stack frame')
		const parsed = frameOf(frame)
		if (parsed) frames.push(parsed)
		if (frame.subFrames !== undefined) {
			if (!Array.isArray(frame.subFrames)) throw new Error('invalid subFrames')
			for (let index = frame.subFrames.length - 1; index >= 0; index--)
				pending.push({ value: frame.subFrames[index], depth: depth + 1 })
		}
	}
	if (!frames.length) throw new Error('callStackTree has no usable frames')
	return frames
}

/** The way most samples went through a sampled tree, entry first. Call only on a tree `walk` accepted. */
function hottestPath(roots: unknown[]): DiagnosticFrame[] {
	const path: DiagnosticFrame[] = []
	const samples = (value: unknown) => {
		const count = object(value)?.sampleCount
		return typeof count === 'number' ? count : 0
	}
	let level = roots
	while (level.length) {
		const frame = object(level.reduce((best, value) => (samples(value) > samples(best) ? value : best)))!
		const parsed = frameOf(frame)
		if (parsed) path.push(parsed)
		level = Array.isArray(frame.subFrames) ? frame.subFrames : []
	}
	return path
}

/**
 * The stack a report is about, innermost frame first. A crash roots each thread's tree at its innermost frame, and the
 * crashed thread is the one marked attributed. A hang is the other way up: each thread is a tree of samples rooted at
 * the thread's entry, with callees as subFrames, and the thread MetricKit marks attributed is not the one that hung.
 * The main thread is (the one entered from dyld), and its stack is the path most samples took, turned innermost first.
 */
export function attributedFrames(payload: Record<string, unknown>, kind: ReportKind): DiagnosticFrame[] {
	const stacks = object(payload.callStackTree)?.callStacks
	if (!Array.isArray(stacks) || stacks.length === 0 || stacks.length > 1024) throw new Error('invalid callStackTree')
	const attributed = () => stacks.find((item) => object(item)?.threadAttributed === true) ?? stacks[0]
	if (kind === 'crash') return walk(object(attributed()))
	const entered = (item: unknown) => {
		const roots = object(item)?.callStackRootFrames
		return Array.isArray(roots) && roots.some((root) => object(root)?.binaryName === 'dyld')
	}
	const stack = object(stacks.find(entered) ?? attributed())
	walk(stack)
	const path = hottestPath(stack!.callStackRootFrames as unknown[]).reverse()
	if (!path.length) throw new Error('callStackTree has no usable frames')
	return path
}

/**
 * The group a report belongs to: its first eight app frames (all frames when none are the app's), by binary and text
 * offset, so ASLR and encoding differences don't split a group. A hang's main thread always passes through the app's
 * `main`, which says nothing about where it hung, so its outermost app frame is left out.
 */
export function signatureFor(payload: Record<string, unknown>, appBinaryName: string, kind: ReportKind): string {
	const frames = attributedFrames(payload, kind)
	const ownFrames = frames.filter((frame) => matchesAppBinary(frame.binaryName, appBinaryName))
	const appFrames = kind === 'hang' ? ownFrames.slice(0, -1) : ownFrames
	return createHash('sha256')
		.update(
			(appFrames.length ? appFrames : frames)
				.slice(0, 8)
				.map((frame) => `${frame.binaryUUID}:${frame.offset}`)
				.join('\n'),
		)
		.digest('hex')
		.slice(0, 16)
}

/** The app's main binary for a bundle id; an unknown bundle id names itself, so it matches nothing. */
export function appBinaryName(binaries: AppBinaries, bundleID: string): string {
	return binaries[bundleID] ?? bundleID
}

/** Xcode's debug dylib holds app code while the small launcher keeps the product name. */
export function matchesAppBinary(binaryName: string, appName: string): boolean {
	return binaryName === appName || binaryName === `${appName}.debug.dylib`
}
