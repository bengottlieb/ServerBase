import { describe, expect, it } from 'vitest'
import { messageSubmissionHash, supportMessageInput } from '../src/index.js'

const id = '11111111-1111-4111-8111-111111111111'

describe('support message input', () => {
	it('trims the text and defaults to no attachments', () => {
		const parsed = supportMessageInput.parse({ id, text: '  help  ' })
		expect(parsed.text).toBe('help')
		expect(parsed.attachments).toEqual([])
	})
	it('refuses a blank or oversized text, a bad id and an unknown category', () => {
		for (const bad of [
			{ id, text: '   ' },
			{ id, text: 'x'.repeat(10001) },
			{ id: 'nope', text: 'x' },
			{ id, text: 'x', category: 'rant' },
		])
			expect(supportMessageInput.safeParse(bad).success).toBe(false)
	})
})

describe('submission hash', () => {
	// A client retries with the same id after a timeout; that must answer the original, but reusing the id for other
	// content, or from the other side of the conversation, must be refused.
	it('is stable for a retry and differs by content and by role', () => {
		const body = supportMessageInput.parse({ id, text: 'help' })
		expect(messageSubmissionHash('customer', body)).toBe(messageSubmissionHash('customer', { ...body }))
		expect(messageSubmissionHash('customer', body)).not.toBe(messageSubmissionHash('staff', body))
		expect(messageSubmissionHash('customer', body)).not.toBe(
			messageSubmissionHash('customer', { ...body, text: 'other' }),
		)
	})
})
