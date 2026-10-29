import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { createInterface } from 'node:readline'
import { fileURLToPath } from 'node:url'
import { type HelperConfig, emit } from './protocol.js'

// In dev mode (`npm run dev`) there is no Swift app: use a fixed port and
// token, and keep the refresh token in a git-ignored file next to the helper.
const devTokenFile = fileURLToPath(new URL('../dev.token', import.meta.url))

export const isDev = process.env.RDF_DEV === '1'

export async function readConfig(): Promise<HelperConfig> {
  if (isDev) {
    return {
      authToken: 'dev',
      port: 8787,
      refreshToken: existsSync(devTokenFile)
        ? readFileSync(devTokenFile, 'utf8').trim() || undefined
        : undefined,
    }
  }

  const rl = createInterface({ input: process.stdin })
  const line = await new Promise<string>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error('No config on stdin within 10s')),
      10_000,
    )
    rl.once('line', (l) => {
      clearTimeout(timer)
      resolve(l)
    })
  })
  rl.close()

  const config = JSON.parse(line) as HelperConfig
  if (!config.authToken) throw new Error('Config is missing authToken')
  return config
}

// Where rotated refresh tokens go: the app (Keychain) or the dev file.
export function persistRefreshToken(value: string) {
  if (isDev) writeFileSync(devTokenFile, value)
  else emit({ type: 'refreshToken', value })
}
