import { z } from 'zod'

// Screenshots in support messages.

export const MAX_ATTACHMENT_BYTES = 1024 * 1024
const encodedImage = z
	.string()
	.max(Math.ceil(MAX_ATTACHMENT_BYTES / 3) * 4)
	.regex(/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/)

/** Only bounded JPEGs, never HTML/SVG or a client-chosen serving type: they are served back as image/jpeg. */
export const supportAttachment = z
	.object({ contentType: z.literal('image/jpeg'), data: encodedImage.meta({ description: 'Base64 JPEG' }) })
	.superRefine((image, ctx) => {
		const bytes = Buffer.from(image.data, 'base64')
		if (bytes.length > MAX_ATTACHMENT_BYTES || !isSupportJPEG(bytes))
			ctx.addIssue({ code: 'custom', message: 'Use a JPEG up to 1 MiB and 2000 pixels per side.' })
	})

/** A whole, well-formed baseline or progressive JPEG of at most 2000 × 2000 pixels, with nothing after its end. */
export function isSupportJPEG(data: Buffer): boolean {
	if (data.length < 4 || data[0] !== 0xff || data[1] !== 0xd8 || data.at(-2) !== 0xff || data.at(-1) !== 0xd9)
		return false
	let offset = 2
	let frame = false
	let scan = false
	while (offset < data.length) {
		if (data[offset++] !== 0xff) return false
		while (data[offset] === 0xff) offset++
		const marker = data[offset++]
		if (marker === 0xd9) return frame && scan && offset === data.length
		if (marker === undefined || offset + 2 > data.length) return false
		const length = data.readUInt16BE(offset)
		if (length < 2 || offset + length > data.length) return false
		if (marker === 0xc0 || marker === 0xc1 || marker === 0xc2) {
			if (length < 11) return false
			const height = data.readUInt16BE(offset + 3)
			const width = data.readUInt16BE(offset + 5)
			const components = data[offset + 7]!
			if (
				width < 1 ||
				height < 1 ||
				width > 2000 ||
				height > 2000 ||
				components < 1 ||
				components > 4 ||
				length !== 8 + 3 * components
			)
				return false
			frame = true
		}
		if (marker === 0xda) {
			if (!frame || length < 6 || length !== 6 + 2 * data[offset + 2]!) return false
			scan = true
			offset += length
			// Entropy-coded data escapes FF bytes and may contain restart markers.
			while (offset < data.length) {
				if (data[offset] !== 0xff) {
					offset++
					continue
				}
				const next = data[offset + 1]
				if (next === 0 || (next !== undefined && next >= 0xd0 && next <= 0xd7)) {
					offset += 2
					continue
				}
				break
			}
		} else offset += length
	}
	return false
}
