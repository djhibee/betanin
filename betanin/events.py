# 3rd party
from flask_restx import marshal
from flask_socketio import ConnectionRefusedError
from flask_jwt_extended import decode_token

# betanin
from betanin.extensions import SOCKETIO
from betanin.rest_models import response


def send_torrent(torrent):
    SOCKETIO.emit("newTorrent", marshal(torrent, response.TORRENT))


def send_line(line):
    SOCKETIO.emit("newLine", marshal(line, response.LINE_WITH_TORRENT_ID))


@SOCKETIO.on("connect")
def on_connect(auth=None):
    token = auth.get("token") if isinstance(auth, dict) else None
    if not token:
        raise ConnectionRefusedError("no token provided")
    try:
        decode_token(token)
    except Exception:
        raise ConnectionRefusedError("invalid token")
