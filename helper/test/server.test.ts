import assert from 'node:assert/strict'
import type { AddressInfo } from 'node:net'
import { after, before, beforeEach, describe, test } from 'node:test'
import { fileURLToPath } from 'node:url'
import { HelperApp, type SignIn } from '../src/app.ts'
import type { SignInResult } from '../src/auth.ts'
import type { CameraSummary, RingGateway } from '../src/ring.ts'
import { createHelperServer } from '../src/server.ts'

class FakeRing implements RingGateway {
  ended: string[] = []
  disconnected = false
  cameras: CameraSummary[] = [
    { id: 1, name: 'Floodlight', model: 'Floodlight Cam', hasBattery: false, batteryLevel: null, isOffline: false },
    { id: 2, name: 'Front Door', model: 'Video Doorbell 2', hasBattery: true, batteryLevel: 72, isOffline: false },
  ]
  async listCameras() {
    return this.cameras
  }
  async startLiveView(cameraId: number, offerSdp: string) {
    return { sessionId: `s-${cameraId}`, answerSdp: `answer-to:${offerSdp}` }
  }
  async endLiveView(sessionId: string) {
    this.ended.push(sessionId)
  }
  async disconnect() {
    this.disconnected = true
  }
}

class FakeSignIn implements SignIn {
  async start(email: string, password: string): Promise<SignInResult> {
    if (password !== 'right') throw new Error('bad password')
    return { status: 'needsCode', prompt: `Enter the code sent to ${email}` }
  }
  async submitCode(code: string): Promise<SignInResult> {
    return code === '123456'
      ? { status: 'signedIn', refreshToken: 'fresh-token' }
      : { status: 'needsCode', prompt: 'Invalid code' }
  }
}

const token = 'test-token'
let baseUrl: string
let server: ReturnType<typeof createHelperServer>
let ring: FakeRing
let persisted: string[]
let app: HelperApp

function setUp(refreshToken?: string) {
  ring = new FakeRing()
  persisted = []
  app = new HelperApp(
    {
      signIn: new FakeSignIn(),
      connect: () => ring,
      persistRefreshToken: (t) => persisted.push(t),
      onSignedOut: () => {},
    },
    refreshToken,
  )
}

async function call(method: string, path: string, body?: unknown, auth = token) {
  const res = await fetch(baseUrl + path, {
    method,
    headers: { authorization: `Bearer ${auth}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  return { status: res.status, body: await res.json() }
}

before(async () => {
  server = createHelperServer({
    // Routes look the app up lazily, so tests can swap it per case.
    app: new Proxy({} as HelperApp, {
      get: (_, key) => {
        const value = (app as any)[key]
        return typeof value === 'function' ? value.bind(app) : value
      },
    }),
    authToken: token,
    playerDir: fileURLToPath(new URL('../player', import.meta.url)),
  })
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r))
  baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`
})

after(() => server.close())

describe('auth guard', () => {
  beforeEach(() => setUp('existing'))

  test('rejects API calls without the per-launch token', async () => {
    const res = await call('GET', '/api/cameras', undefined, 'wrong')
    assert.equal(res.status, 401)
  })

  test('serves the player without a token', async () => {
    const res = await fetch(baseUrl + '/player')
    assert.equal(res.status, 200)
    assert.match(await res.text(), /player\.js/)
  })
})

describe('signed out', () => {
  beforeEach(() => setUp())

  test('reports signed out and refuses camera calls', async () => {
    assert.deepEqual((await call('GET', '/api/status')).body, { signedIn: false })
    assert.equal((await call('GET', '/api/cameras')).status, 409)
  })

  test('signs in through 2FA, persists the token, and never returns it', async () => {
    const first = await call('POST', '/api/auth/sign-in', { email: 'me@example.com', password: 'right' })
    assert.equal(first.body.status, 'needsCode')

    const wrong = await call('POST', '/api/auth/code', { code: '000000' })
    assert.deepEqual(wrong.body, { status: 'needsCode', prompt: 'Invalid code' })

    const ok = await call('POST', '/api/auth/code', { code: '123456' })
    assert.deepEqual(ok.body, { status: 'signedIn' })
    assert.deepEqual(persisted, ['fresh-token'])
    assert.deepEqual((await call('GET', '/api/status')).body, { signedIn: true })
  })

  test('surfaces a bad password as an error', async () => {
    const res = await call('POST', '/api/auth/sign-in', { email: 'me@example.com', password: 'nope' })
    assert.equal(res.status, 500)
    assert.equal(res.body.error, 'bad password')
  })
})

describe('live view', () => {
  beforeEach(() => setUp('existing'))

  test('lists cameras', async () => {
    const res = await call('GET', '/api/cameras')
    assert.deepEqual(res.body.map((c: CameraSummary) => c.name), ['Floodlight', 'Front Door'])
  })

  test('includes battery level, null for wired cameras', async () => {
    const res = await call('GET', '/api/cameras')
    assert.deepEqual(res.body.map((c: CameraSummary) => c.batteryLevel), [null, 72])
  })

  test('relays the offer to Ring and returns its answer', async () => {
    const res = await call('POST', '/api/live', { cameraId: 1, sdp: 'offer' })
    assert.deepEqual(res.body, { sessionId: 's-1', sdp: 'answer-to:offer' })
  })

  test('ends a session', async () => {
    await call('DELETE', '/api/live/s-1')
    assert.deepEqual(ring.ended, ['s-1'])
  })

  test('validates the request body', async () => {
    assert.equal((await call('POST', '/api/live', { cameraId: '1', sdp: 'x' })).status, 400)
  })

  test('sign out disconnects from Ring', async () => {
    await call('POST', '/api/auth/sign-out')
    assert.equal(ring.disconnected, true)
    assert.deepEqual((await call('GET', '/api/status')).body, { signedIn: false })
  })
})
