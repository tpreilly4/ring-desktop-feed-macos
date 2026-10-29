// Live player. Loaded by the app's WKWebView (or a browser in dev mode) as
//   /player#token=<bearer>&camera=<id>&autoReconnect=1&muted=1
// The browser's own WebRTC offer is sent to Ring via the helper, so video and
// audio flow straight from Ring into this page.

const params = new URLSearchParams(location.hash.slice(1))
const token = params.get('token') ?? ''
const autoReconnect = params.get('autoReconnect') === '1'

const video = document.getElementById('video')
const statusEl = document.getElementById('status')
const overlay = document.getElementById('overlay')
const overlayText = document.getElementById('overlay-text')
const resumeButton = document.getElementById('resume')
const camerasEl = document.getElementById('cameras')

// Same STUN server ring-client-api uses for its own WebRTC sessions.
const iceServers = [{ urls: 'stun:stun.kinesisvideo.us-east-1.amazonaws.com:443' }]

let cameraId = Number(params.get('camera')) || undefined
let pc
let sessionId
let wantLive = false

video.muted = params.get('muted') !== '0'

function setState(state, detail = '') {
  statusEl.dataset.state = state
  statusEl.textContent = { connecting: 'Connecting…', live: 'Live', ended: 'Ended', error: 'Error', idle: '' }[state]
  statusEl.style.display = state === 'idle' ? 'none' : ''
  overlay.classList.toggle('shown', state === 'ended' || state === 'error')
  overlayText.textContent = detail
  // Let the Swift side follow along, if we're inside the app.
  window.webkit?.messageHandlers?.rdf?.postMessage({ state, detail, sessionId })
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error ?? `HTTP ${res.status}`)
  return json
}

function waitForIceGathering(peer, timeoutMs = 3000) {
  // Ring's endpoint takes one complete offer (no trickle ICE), so wait for
  // candidates — but don't hang forever on a slow STUN server.
  if (peer.iceGatheringState === 'complete') return Promise.resolve()
  return new Promise((resolve) => {
    const done = () => {
      peer.removeEventListener('icegatheringstatechange', check)
      resolve()
    }
    const check = () => peer.iceGatheringState === 'complete' && done()
    peer.addEventListener('icegatheringstatechange', check)
    setTimeout(done, timeoutMs)
  })
}

async function start() {
  if (!cameraId) return
  wantLive = true
  await teardown()
  setState('connecting')

  const peer = new RTCPeerConnection({ iceServers })
  pc = peer
  peer.addTransceiver('video', { direction: 'recvonly' })
  peer.addTransceiver('audio', { direction: 'recvonly' })

  const stream = new MediaStream()
  video.srcObject = stream
  peer.ontrack = ({ track }) => stream.addTrack(track)
  peer.onconnectionstatechange = () => {
    if (pc !== peer) return
    const s = peer.connectionState
    if (s === 'connected') setState('live')
    // Ring ends streams after ~10 minutes; it shows up as a dropped connection.
    if (s === 'failed' || s === 'disconnected' || s === 'closed') ended('The live view ended.')
  }

  try {
    await peer.setLocalDescription(await peer.createOffer())
    await waitForIceGathering(peer)
    const answer = await api('POST', '/api/live', { cameraId, sdp: peer.localDescription.sdp })
    if (pc !== peer) return
    sessionId = answer.sessionId
    await peer.setRemoteDescription({ type: 'answer', sdp: answer.sdp })
  } catch (e) {
    if (pc !== peer) return
    await teardown()
    setState('error', e.message)
  }
}

async function ended(detail) {
  await teardown()
  if (wantLive && autoReconnect) {
    start()
  } else {
    setState('ended', detail)
  }
}

async function teardown() {
  const peer = pc
  const id = sessionId
  pc = undefined
  sessionId = undefined
  peer?.close()
  if (id) await api('DELETE', `/api/live/${id}`).catch(() => {})
}

async function stop() {
  wantLive = false
  await teardown()
  setState('idle')
}

async function showCameraPicker() {
  // Dev convenience: with no camera in the URL, list them.
  try {
    const cameras = await api('GET', '/api/cameras')
    for (const camera of cameras) {
      const button = document.createElement('button')
      button.type = 'button'
      button.textContent = `${camera.name}${camera.hasBattery ? ' (battery)' : ''}`
      button.onclick = () => {
        camerasEl.classList.remove('shown')
        cameraId = camera.id
        start()
      }
      camerasEl.append(button)
    }
    camerasEl.classList.add('shown')
  } catch (e) {
    setState('error', e.message)
  }
}

resumeButton.onclick = () => start()
window.addEventListener('pagehide', () => {
  if (sessionId) {
    fetch(`/api/live/${sessionId}`, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${token}` },
      keepalive: true,
    })
  }
})

// Hooks for the Swift side (evaluateJavaScript).
window.rdf = {
  start: (id) => {
    if (id) cameraId = id
    return start()
  },
  stop,
  setMuted: (muted) => {
    video.muted = muted
  },
}

setState('idle')
if (cameraId) start()
else showCameraPicker()
