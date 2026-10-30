// Messages the helper writes to stdout, one JSON object per line.
// The Swift app reads these to learn the port, persist rotated tokens, etc.
// Anything else (logs) goes to stderr.

export type HelperEvent =
  | { type: 'ready'; port: number }
  | { type: 'refreshToken'; value: string }
  // 'expired' means Ring refused the token, so the user must sign in again.
  | { type: 'signedOut'; reason: 'user' | 'expired' }
  | { type: 'reachability'; reachable: boolean }
  | { type: 'error'; message: string }
  // A motion or doorbell push arrived for a camera.
  | { type: 'motion' | 'ding'; cameraId: number; cameraName: string }

export function emit(event: HelperEvent) {
  process.stdout.write(JSON.stringify(event) + '\n')
}

// Startup config the app sends as the first line on stdin.
export interface HelperConfig {
  // Bearer token every HTTP request must carry. Random per launch.
  authToken: string
  // Ring refresh token from the Keychain, if signed in.
  refreshToken?: string
  // 0 = pick a random free port.
  port: number
}

export function log(...args: unknown[]) {
  console.error(new Date().toISOString(), ...args)
}
