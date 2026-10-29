import { fileURLToPath } from 'node:url'
import { HelperApp } from './app.js'
import { SignInFlow } from './auth.js'
import { isDev, persistRefreshToken, readConfig } from './config.js'
import { emit, log } from './protocol.js'
import { RingAccount } from './ring.js'
import { createHelperServer } from './server.js'

const config = await readConfig()

const app = new HelperApp(
  {
    signIn: new SignInFlow(),
    connect: (token) => new RingAccount(token, persistRefreshToken),
    persistRefreshToken,
    onSignedOut: () => emit({ type: 'signedOut', reason: 'user' }),
  },
  config.refreshToken,
)

const server = createHelperServer({
  app,
  authToken: config.authToken,
  playerDir: fileURLToPath(new URL('../player', import.meta.url)),
})

server.listen(config.port, '127.0.0.1', () => {
  const address = server.address()
  const port = typeof address === 'object' && address ? address.port : config.port
  emit({ type: 'ready', port })
  log(`helper listening on 127.0.0.1:${port}${isDev ? ' (dev mode, token "dev")' : ''}`)
})

async function shutdown() {
  await app.ring()?.disconnect()
  process.exit(0)
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)
// The app owns us: if it goes away (stdin closes), so do we.
if (!isDev) process.stdin.on('end', shutdown).resume()
