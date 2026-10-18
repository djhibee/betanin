import backend from '@/backend'
import authUtils from '@/authentication_utilities'
import router from '@/router'
import socket from '@/socket'

export default {
  async login(username, password) {
    try {
      const response = await backend.insecureAxios.post('authentication/login', { username, password })
      authUtils.setToken(response.data.token)
      socket.connect()
      router.replace(router.currentRoute.query.redirect || '/')
    } catch (error) {
      if (error.response !== undefined && [422, 429].includes(error.response.status)) {
        return error.response.data.message
      } else {
        return 'unexpected error while fetching a token from the backend'
      }
    }
  },
  logout(redirect) {
    authUtils.clearToken()
    socket.disconnect()
    router.replace({
      name: 'login',
      query: { redirect },
    })
  },
}
