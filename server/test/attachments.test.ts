import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import { MAX_ATTACHMENT_BYTES, isSupportJPEG, supportAttachment, supportMessageInput } from '../src/index.js'

// Attachments are served back as image/jpeg to staff and customers, so only a whole, bounded JPEG may be stored: never
// HTML, SVG or a client-chosen type.
const jpeg = readFileSync(new URL('./fixtures/support.jpg', import.meta.url))
const image = { contentType: 'image/jpeg', data: jpeg.toString('base64') }

describe('support attachments', () => {
	it('accepts a real JPEG', () => {
		expect(isSupportJPEG(jpeg)).toBe(true)
		expect(supportAttachment.safeParse(image).success).toBe(true)
	})
	it('refuses disguised, malformed, truncated and oversized data', () => {
		const png = Buffer.from('\x89PNG\r\n').toString('base64')
		for (const attachment of [
			{ ...image, data: png },
			{ ...image, data: 'abcd' },
			{ ...image, data: '!!!!' },
			{ ...image, contentType: 'image/svg+xml' },
			{ ...image, contentType: 'text/html' },
			{ ...image, data: jpeg.subarray(0, jpeg.length - 4).toString('base64') },
			{ ...image, data: Buffer.alloc(MAX_ATTACHMENT_BYTES + 1).toString('base64') },
		])
			expect(supportAttachment.safeParse(attachment).success).toBe(false)
	})
	it('refuses a frame beyond 2000 pixels a side, and trailing bytes after the end marker', () => {
		const huge = Buffer.from(jpeg)
		huge.writeUInt16BE(30000, huge.indexOf(Buffer.from([255, 192])) + 7)
		expect(supportAttachment.safeParse({ ...image, data: huge.toString('base64') }).success).toBe(false)
		expect(isSupportJPEG(Buffer.concat([jpeg, Buffer.from([0])]))).toBe(false)
	})
	it('allows at most three per message', () => {
		const body = { id: crypto.randomUUID(), text: 'x' }
		expect(supportMessageInput.safeParse({ ...body, attachments: Array(3).fill(image) }).success).toBe(true)
		expect(supportMessageInput.safeParse({ ...body, attachments: Array(4).fill(image) }).success).toBe(false)
	})
})
