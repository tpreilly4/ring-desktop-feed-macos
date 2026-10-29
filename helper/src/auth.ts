import { RingRestClient } from 'ring-client-api/rest-client'

export type SignInResult =
  | { status: 'signedIn'; refreshToken: string }
  | { status: 'needsCode'; prompt: string }

// Ring's email/password sign-in, including the 2FA step. The password is
// only held in memory for the duration of the sign-in attempt.
export class SignInFlow {
  private pending?: RingRestClient

  async start(email: string, password: string): Promise<SignInResult> {
    const client = new RingRestClient({
      email,
      password,
      controlCenterDisplayName: 'Ring Desktop Feed',
    })
    try {
      const auth = await client.getCurrentAuth()
      return { status: 'signedIn', refreshToken: auth.refresh_token }
    } catch (e) {
      if (!client.promptFor2fa) throw e
      this.pending = client
      return { status: 'needsCode', prompt: client.promptFor2fa }
    }
  }

  async submitCode(code: string): Promise<SignInResult> {
    const client = this.pending
    if (!client) throw new Error('No sign-in in progress')
    try {
      const auth = await client.getAuth(code)
      this.pending = undefined
      return { status: 'signedIn', refreshToken: auth.refresh_token }
    } catch (e) {
      // Wrong code: keep the pending client so the user can try again.
      if (client.promptFor2fa) {
        return { status: 'needsCode', prompt: client.promptFor2fa }
      }
      this.pending = undefined
      throw e
    }
  }
}
