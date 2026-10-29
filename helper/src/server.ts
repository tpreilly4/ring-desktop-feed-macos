import { readFile } from 'node:fs/promises'
import { type IncomingMessage, type ServerResponse, createServer } from 'node:http'
import { join } from 'node:path'
import type { HelperApp } from './app.js'
import { log } from './protocol.js'
import { HttpError } from './ring.js'

export interface ServerOptions {
  app: HelperApp
  authToken: string
  playerDir: string
}

const staticFiles: Record<string, { file: string; type: string }> = {
  '/player': { file: 'index.html', type: 'text/html; charset=utf-8' },
  '/player/player.js': { file: 'player.js', type: 'text/javascript; charset=utf-8' },
}

// Local-only HTTP API. /player* is static and public (it holds no data); every
// /api route needs the per-launch bearer token.
export function createHelperServer({ app, authToken, playerDir }: ServerOptions) {
  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? '/', 'http://localhost')
      const asset = staticFiles[url.pathname]

      if (!isLocalHost(req.headers.host)) throw new HttpError(403, 'Bad host')
      if (asset && req.method === 'GET') {
        res.writeHead(200, { 'content-type': asset.type, 'cache-control': 'no-store' })
        res.end(await readFile(join(playerDir, asset.file)))
        return
      }
      if (!url.pathname.startsWith('/api/')) throw new HttpError(404, 'Not found')
      if (req.headers.authorization !== `Bearer ${authToken}`) {
        throw new HttpError(401, 'Missing or wrong token')
      }

      sendJson(res, 200, await route(app, req, url))
    } catch (e) {
      const status = e instanceof HttpError ? e.status : 500
      if (status === 500) log('request failed', req.method, req.url, e)
      sendJson(res, status, { error: e instanceof Error ? e.message : String(e) })
    }
  })
}

async function route(app: HelperApp, req: IncomingMessage, url: URL): Promise<unknown> {
  const key = `${req.method} ${url.pathname}`

  switch (key) {
    case 'GET /api/status':
      return { signedIn: app.signedIn }
    case 'POST /api/auth/sign-in': {
      const { email, password } = await readJson(req)
      if (!email || !password) throw new HttpError(400, 'email and password are required')
      return app.signIn(email, password)
    }
    case 'POST /api/auth/code': {
      const { code } = await readJson(req)
      if (!code) throw new HttpError(400, 'code is required')
      return app.submitCode(String(code))
    }
    case 'POST /api/auth/sign-out':
      await app.signOut()
      return { status: 'signedOut' }
    case 'GET /api/cameras':
      return requireRing(app).listCameras()
    case 'POST /api/live': {
      const { cameraId, sdp } = await readJson(req)
      if (typeof cameraId !== 'number' || !sdp) {
        throw new HttpError(400, 'cameraId (number) and sdp are required')
      }
      const { sessionId, answerSdp } = await requireRing(app).startLiveView(cameraId, sdp)
      return { sessionId, sdp: answerSdp }
    }
  }

  const live = url.pathname.match(/^\/api\/live\/([\w-]+)$/)
  if (live && req.method === 'DELETE') {
    await requireRing(app).endLiveView(live[1])
    return { status: 'ended' }
  }

  throw new HttpError(404, 'Not found')
}

function requireRing(app: HelperApp) {
  const ring = app.ring()
  if (!ring) throw new HttpError(409, 'Not signed in to Ring')
  return ring
}

function isLocalHost(host: string | undefined) {
  // Guards against DNS rebinding: only accept requests addressed to loopback.
  return !!host && /^(127\.0\.0\.1|localhost)(:\d+)?$/.test(host)
}

async function readJson(req: IncomingMessage): Promise<Record<string, any>> {
  let body = ''
  for await (const chunk of req) {
    body += chunk
    if (body.length > 1_000_000) throw new HttpError(413, 'Body too large')
  }
  try {
    return body ? JSON.parse(body) : {}
  } catch {
    throw new HttpError(400, 'Body is not JSON')
  }
}

function sendJson(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'content-type': 'application/json' })
  res.end(JSON.stringify(body))
}
