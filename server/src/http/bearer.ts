import { createHash, timingSafeEqual } from 'node:crypto'

const hash = (value: string) => createHash('sha256').update(value).digest()

/** Whether an Authorization header is `Bearer <token>`, compared in constant time. False without a token. */
export function bearerMatches(authorization: string | undefined, token: string | undefined): boolean {
	if (!token) return false
	return timingSafeEqual(hash(authorization ?? ''), hash(`Bearer ${token}`))
}
