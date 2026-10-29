import type { SignInResult } from './auth.js'
import type { RingGateway } from './ring.js'

export interface SignIn {
  start(email: string, password: string): Promise<SignInResult>
  submitCode(code: string): Promise<SignInResult>
}

export interface AppDeps {
  signIn: SignIn
  connect(refreshToken: string): RingGateway
  persistRefreshToken(token: string): void
  onSignedOut(): void
}

// Holds the signed-in Ring account, if any, and moves between signed-out and
// signed-in. The HTTP layer talks only to this.
export class HelperApp {
  private gateway?: RingGateway

  constructor(
    private readonly deps: AppDeps,
    refreshToken?: string,
  ) {
    if (refreshToken) this.gateway = deps.connect(refreshToken)
  }

  get signedIn() {
    return this.gateway !== undefined
  }

  ring(): RingGateway | undefined {
    return this.gateway
  }

  async signIn(email: string, password: string) {
    return this.finish(await this.deps.signIn.start(email, password))
  }

  async submitCode(code: string) {
    return this.finish(await this.deps.signIn.submitCode(code))
  }

  async signOut() {
    await this.gateway?.disconnect()
    this.gateway = undefined
    this.deps.onSignedOut()
  }

  private async finish(result: SignInResult) {
    if (result.status === 'signedIn') {
      await this.gateway?.disconnect()
      this.deps.persistRefreshToken(result.refreshToken)
      this.gateway = this.deps.connect(result.refreshToken)
    }
    // Never hand the token itself back over HTTP.
    return result.status === 'signedIn'
      ? { status: 'signedIn' as const }
      : result
  }
}
