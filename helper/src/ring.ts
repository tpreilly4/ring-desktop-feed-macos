import { PushNotificationAction, RingApi, type RingCamera } from 'ring-client-api'
import { log } from './protocol.js'

type SimpleWebRtcSession = ReturnType<RingCamera['createSimpleWebRtcSession']>

export interface CameraSummary {
  id: number
  name: string
  model: string
  hasBattery: boolean
  // 0–100, or null when Ring doesn't report one (e.g. wired cameras).
  batteryLevel: number | null
  isOffline: boolean
}

export interface LiveViewStart {
  sessionId: string
  answerSdp: string
}

// Everything the HTTP layer needs from Ring. Tests swap in a fake.
export interface RingGateway {
  listCameras(): Promise<CameraSummary[]>
  // The player's own WebRTC offer goes to Ring and Ring answers it, so media
  // flows straight from Ring to the player with no re-encoding in between.
  startLiveView(cameraId: number, offerSdp: string): Promise<LiveViewStart>
  endLiveView(sessionId: string): Promise<void>
  disconnect(): Promise<void>
}

export interface CameraEvent {
  kind: 'motion' | 'ding'
  cameraId: number
  cameraName: string
}

export class RingAccount implements RingGateway {
  private readonly api: RingApi
  private readonly sessions = new Map<string, SimpleWebRtcSession>()

  constructor(refreshToken: string, onRefreshToken: (token: string) => void) {
    this.api = new RingApi({
      refreshToken,
      controlCenterDisplayName: 'Ring Desktop Feed',
      // Never wake battery cameras just for a periodic snapshot.
      avoidSnapshotBatteryDrain: true,
      // Keeps battery level and online status fresh. This is a REST poll,
      // it doesn't wake the cameras.
      cameraStatusPollingSeconds: 300,
    })
    this.api.onRefreshTokenUpdated.subscribe(({ newRefreshToken }) =>
      onRefreshToken(newRefreshToken),
    )
  }

  async listCameras(): Promise<CameraSummary[]> {
    const cameras = await this.api.getCameras()
    return cameras.map(summarize)
  }

  async startLiveView(cameraId: number, offerSdp: string): Promise<LiveViewStart> {
    const camera = await this.camera(cameraId)
    const session = camera.createSimpleWebRtcSession()
    const answerSdp = await session.start(offerSdp)
    this.sessions.set(session.sessionId, session)
    log(`live view started: ${camera.name} (${session.sessionId})`)
    return { sessionId: session.sessionId, answerSdp }
  }

  async endLiveView(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId)
    if (!session) return
    this.sessions.delete(sessionId)
    await session.end().catch((e) => log('failed to end live view', e))
    log(`live view ended: ${sessionId}`)
  }

  // Reports motion and doorbell pushes for as long as this account is connected.
  async watchEvents(onEvent: (event: CameraEvent) => void) {
    const cameras = await this.api.getCameras()
    for (const camera of cameras) {
      camera.onNewNotification.subscribe((push) => {
        const kind = push.android_config.category === PushNotificationAction.Ding ? 'ding' : 'motion'
        log(`${kind} on ${camera.name}`)
        onEvent({ kind, cameraId: camera.id, cameraName: camera.name })
      })
    }
  }

  async disconnect() {
    await Promise.all([...this.sessions.keys()].map((id) => this.endLiveView(id)))
    this.api.disconnect()
  }

  private async camera(id: number): Promise<RingCamera> {
    const camera = (await this.api.getCameras()).find((c) => c.id === id)
    if (!camera) throw new HttpError(404, `No camera with id ${id}`)
    return camera
  }
}

function summarize(camera: RingCamera): CameraSummary {
  return {
    id: camera.id,
    name: camera.name,
    model: camera.model,
    hasBattery: camera.hasBattery,
    batteryLevel: camera.batteryLevel,
    isOffline: camera.isOffline,
  }
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message)
  }
}
