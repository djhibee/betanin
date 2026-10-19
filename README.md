<p align="center">
<img width="300" src="https://github.com/sentriz/betanin/raw/master/.github/logo.png">
</p>
<h4 align="center">
<a href="http://beets.io/">beets.io</a> based man-in-the-middle of your
torrent client and music player
</h4>
<p align="center">
<a href="http://hub.docker.com/r/sentriz/betanin"><img src="https://img.shields.io/docker/pulls/sentriz/betanin.svg"></a>
<img src="https://img.shields.io/github/issues/sentriz/betanin.svg">
<img src="https://img.shields.io/github/issues-pr/sentriz/betanin.svg">
</p>
<hr>

### workflow

<p align="center">
<img src="https://github.com/sentriz/betanin/raw/master/.github/flow.png">
</p>
<hr>

### notifiers

betanin uses [apprise](https://github.com/caronc/apprise) for
notifications. so anything supported there will work. but some include

- email
- discord
- telegram
- emby

<hr>

### installation (without Docker)

```shell
step1. (optional, do it if you want to isolate your install) python -m venv betanin-env
step2. (optional, fo itif step 2.) source betanin-env/bin/activate
# !Warning! "pip install --user betanin" uses PyPi (including betanin_client/dist/) and thus will fetch origin repo from  sentriz
# Install backend only
step3. pip install git+https://github.com/djhibee/betanin
# Install with frontend from localrepo
step3bis.
a. git clone https://github.com/djhibee/betanin
# build UI locally from the clone repo
b. cd betanin_client && run npm ci && npm run build
# install backend
c. cd .. && pip install .
```

<hr>

### usage

```shell
# start server
betanin
# a config file will be created, add your credentials to it
# start again
betanin [--host=<host>] [--port=<port>]
# ui will be available at port
# you may also use env vars instead, eg
BETANIN_HOST=0.0.0.0 betanin
BETANIN_PORT=4030 betanin

# optionally start cli (for db operations, debugging)
betanin-shell
# or if docker
docker exec -it <container_id> betanin-shell
```

<hr>

### screenshots

<p align="center">
<img src="https://github.com/sentriz/betanin/raw/master/.github/scrot_1.png">
</p>
<p align="center">
<img src="https://github.com/sentriz/betanin/raw/master/.github/scrot_2.png">
</p>
<p align="center">
<img src="https://github.com/sentriz/betanin/raw/master/.github/scrot_3.png">
</p>
<p align="center">
<img src="https://github.com/sentriz/betanin/raw/master/.github/scrot_4.png">
</p>
<hr>

### docker

###### image

`docker pull djhibee/betanin`

###### volumes `/b/.local/share/betanin/` for a persistent database

`/b/.config/betanin/` for a persistent betanin config  
`/b/.config/beets/` for a persistent beets home (point this to your
current beets home if you have one)  
`/music/` so beets can access your music  
`/downloads/` so beets can access your downloads

###### compose

```yml
betanin:
  image: djhibee/betanin
  ports:
    - 9393:9393
  restart: unless-stopped
  environment:
    - UID=1000 # (optionally) set user id
    - GID=1000 # (optionally) set group id
  volumes:
    - ${DATA}/betanin/data:/b/.local/share/betanin/
    - ${DATA}/betanin/config:/b/.config/betanin/
    - ${DATA}/betanin/beets:/b/.config/beets/
    - ${MEDIA}/music:/music/
    - ${MEDIA}/downloads:/downloads/
```

###### hardening

betanin is meant for a trusted local network. a few cheap settings reduce what
is exposed, see the hardened compose below

- **publish the port on one address only.** `9393:9393` listens on every
  interface of the host (`0.0.0.0` and `[::]`), including VPNs and IPv6, and
  docker's rules bypass ufw/firewalld. use `127.0.0.1:9393:9393` if only a
  reverse proxy on the same host talks to betanin, or the host's LAN address
  (e.g. `192.168.1.10:9393:9393`, give the host a fixed IP) for direct LAN
  access. check with `docker port betanin`. also make sure your router does not
  forward (or UPnP-open) the port
- **put an HTTPS reverse proxy in front** if anyone else on the network uses it.
  betanin speaks plain HTTP, so the password, the session token and the API key
  otherwise cross the network in clear text. the proxy must forward
  `X-Forwarded-Proto` and `X-Forwarded-Host` (websocket connections are
  same-origin only), or list the URL the UI is reached from in `config.toml`:
  `[server] socket_allowed_origins = ["https://betanin.lan"]`. the login rate
  limit is per client IP, which is the proxy's IP behind a proxy, so rate-limit
  there too
- **drop capabilities.** the entrypoint only needs root to create the user,
  `chown` the volumes and switch user, so `cap_drop: [ALL]` with `CHOWN`,
  `SETUID` and `SETGID` is enough, and `no-new-privileges` stops anything in the
  container from gaining privileges through setuid binaries. betanin itself runs
  as `UID`/`GID` with no capabilities at all. two notes:
  - with this set the log shows a harmless `adduser: /b: Operation not
    permitted` (add `FOWNER` to silence it)
  - if files in the volumes belong to another user and are not readable by
    root (e.g. mode `700`), the `chown` fails and betanin cannot write them:
    `chown` them once on the host, or add `DAC_OVERRIDE`
- **store the password hashed.** `[frontend] password` in `config.toml` can be a
  hash instead of plain text:
  `docker exec -it betanin betanin-hash-password` (prompts for the password),
  then paste the `scrypt:...` output as the password value
- **set `UID`/`GID`** to an unprivileged user. with `UID=0` betanin and beets run
  as root
- optionally, restrict imports to your downloads directory with
  `[server] import_roots = ["/downloads"]` in `config.toml`

```yml
betanin:
  image: sentriz/betanin
  container_name: betanin
  ports:
    - 127.0.0.1:9393:9393 # or <host LAN IP>:9393:9393
  restart: unless-stopped
  environment:
    - UID=1000
    - GID=1000
  cap_drop:
    - ALL
  cap_add:
    - CHOWN
    - SETUID
    - SETGID
  security_opt:
    - no-new-privileges:true
  volumes:
    - ${DATA}/betanin/data:/b/.local/share/betanin/
    - ${DATA}/betanin/config:/b/.config/betanin/
    - ${DATA}/betanin/beets:/b/.config/beets/
    - ${MEDIA}/music:/music/
    - ${MEDIA}/downloads:/downloads/
```

<hr>

### transmission

create a script named `done.sh` or anything you like, and make it
executable:  
`chmod +x done.sh`

###### settings.json (example excerpt)

```json
...
"script-torrent-done-enabled": true,
"script-torrent-done-filename": "/scripts/done.sh",
...
```

###### done script

```bash
#!/bin/sh

curl \
    --request POST \
    --data-urlencode "path=<path_to_transmission_downloads>" \
    --data-urlencode "name=$TR_TORRENT_NAME" \
    --header "X-API-Key: <your_api_key>" \
    "https://betanin.example.com/api/torrents"
```

###### transmission docker compose (excerpt)

```yaml
volumes:
  - ${DATA}/transmission/config:/config
  - ${DATA}/transmission/scripts:/scripts
  - ${MEDIA}/download:/downloads
```

<hr>

### deluge

create a script named `done.sh` or anything you like, and make it
executable:  
`chmod +x done.sh`  
you must also be using the
[Execute](https://dev.deluge-torrent.org/wiki/Plugins/Execute) plugin,
set to the `Torrent Complete` event

###### done script

```bash
#!/bin/sh

curl \
    --request POST \
    --data-urlencode "path=<path_to_deluge_downloads>" \
    --data-urlencode "name=$2" \
    --header "X-API-Key: <your_api_key>" \
    "https://betanin.example.com/api/torrents"
```

<hr>

### qbittorrent

create a script named `done.sh` or anything you like, and make it
executable:  
`chmod +x done.sh`

open qbittorrent `Tools` > `Options` > check `Run external program on torrent completion`

set the path to the above `done.sh` and arguments such as

```
/path/to/done.sh "%L" "%R"
```

###### done script

```bash
#!/bin/sh

echo "category: $1"
echo "path: $2"

[ "$1" != "music" ] && exit

curl \
    --request POST \
    --data-urlencode "both=$2" \
    --header "X-API-Key: <your_api_key>" \
    "https://betanin.example.com/api/torrents"
```

now any music downloaded to the **music** category will be imported by betanin

<hr>

### developing

###### working on the backend

there is not much else to do, write your code,
`python -m betanin.entry.betanin`, kill it, write your code, etc. the
webserver will be available at _<http://localhost:9393/>_. the static
frontend is served at `/`, and the api is served at `/api`. (there is a
swagger ui there too) also see `python -m betanin.entry.shell`.  
if you need to do a manual migration do
`env FLASK_APP='betanin.application:create' flask db migrate --directory betanin_migrations/`
(then upgrades are automatically done on betanin start)

###### working on the frontend

start the backend with `python -m betanin.entry.betanin`, but don’t use
the static frontend served at _<http://localhost:9393/>_. Instead, in a
new shell, do `npm --prefix betanin_client/ run serve` and use the
frontend served at _<http://localhost:8081/>_. it will look for a backend
listening on port 9393 locally. after that you can edit anything in
`betanin_client/src`, it will be linted and automatically reflected in
your web browser.
