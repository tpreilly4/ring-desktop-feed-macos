// `npm run sign-in`: sign in to Ring from the terminal (email, password, 2FA)
// and store the refresh token in dev.token for `npm run dev`. The app has its
// own sign-in screen; this is only for working on the helper by itself.
import { writeFileSync } from 'node:fs'
import { createInterface } from 'node:readline/promises'
import { fileURLToPath } from 'node:url'
import { SignInFlow } from './auth.js'

const rl = createInterface({ input: process.stdin, output: process.stdout })
const flow = new SignInFlow()

let result = await flow.start(await rl.question('Ring email: '), await rl.question('Password: '))
while (result.status === 'needsCode') {
  result = await flow.submitCode(await rl.question(`${result.prompt}: `))
}
rl.close()

writeFileSync(fileURLToPath(new URL('../dev.token', import.meta.url)), result.refreshToken)
console.log('\nSigned in. Token saved to helper/dev.token (git-ignored). Now run `npm run dev`.')
process.exit(0)
