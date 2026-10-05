import { createHash } from 'node:crypto'
import { z } from 'zod'
import { supportAttachment } from './attachments.js'

// A support-chat message as a client sends it, and the hash that makes a retry idempotent.

export const SUPPORT_CATEGORIES = ['bug', 'suggestion', 'comment'] as const
export const MAX_MESSAGE_ATTACHMENTS = 3
export const MAX_MESSAGE_TEXT = 10000
export type SupportRole = 'customer' | 'staff'

export const supportMessageInput = z.object({
	id: z.uuid(),
	text: z.string().trim().min(1).max(MAX_MESSAGE_TEXT),
	category: z.enum(SUPPORT_CATEGORIES).optional(),
	appInfo: z
		.object({
			bundleID: z.string().max(200),
			version: z.string().max(100),
			build: z.string().max(100),
			osVersion: z.string().max(200),
		})
		.optional(),
	attachments: z.array(supportAttachment).max(MAX_MESSAGE_ATTACHMENTS).default([]),
})
export type SupportMessageInput = z.infer<typeof supportMessageInput>

/**
 * What identifies a submission: a retry with the same id and the same hash answers the original; the same id with a
 * different hash (other content, or the other role) is a conflict.
 */
export function messageSubmissionHash(role: SupportRole, body: SupportMessageInput): string {
	return createHash('sha256')
		.update(JSON.stringify({ role, ...body }))
		.digest('hex')
}
