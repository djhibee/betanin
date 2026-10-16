import IO from 'socket.io-client'
import authUtils from '@/authentication_utilities'
import { SOCKET_URL } from '@/constants'

// the server refuses connections without a valid jwt, so only connect once
// we have a token, and send it (re-read on every (re)connection attempt)
const socket = IO(SOCKET_URL, {
  autoConnect: false,
  auth: (cb) => cb({ token: authUtils.getToken() }),
})

export default {
  socket,
  connect() {
    if (authUtils.isLoggedIn() && !socket.active) socket.connect()
  },
  disconnect() {
    socket.disconnect()
  },
}
