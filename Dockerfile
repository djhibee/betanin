# Base images are digest-pinned. Tags move; digests do not, and the point of
# this fork is that a build in six months produces the same image as a build
# today. See docs/FORK.md.
#
# Note this pins the OS layer going forward, not backwards: the apk packages
# here are alpine 3.24 (python 3.14) as of the pin date; the base moved
# 3.18 (EOL) -> 3.22 -> 3.24. What is reproduced exactly is the
# Python dependency tree, which is where beets and all of our match tuning
# live. See requirements-docker.txt.

# node 22 (v22.23.3, alpine 3.24). The frontend is built with webpack 4, which
# needs the legacy OpenSSL provider on node >= 17.
FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS builder-frontend
# --- AVANT ---
# WORKDIR /src
# COPY betanin_client/ .
# RUN npm install && ...

# --- APRÈS OPTIMISATION DU CACHE NPM ---
WORKDIR /src
# 1. Copier uniquement les fichiers de configuration des dépendances
COPY betanin_client/package.json betanin_client/package-lock.json ./
# 2. Installer les dépendances (cette étape restera dans le cache Docker)
RUN npm ci 
# 3. Copier le reste du code source du client pour lancer le build
COPY betanin_client/ .
RUN NODE_OPTIONS=--openssl-legacy-provider PRODUCTION=true npm run-script build


FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS builder-mp3val
WORKDIR /tmp
COPY alpine/mp3val/APKBUILD .
RUN apk update && \
    apk add --no-cache abuild && \
    abuild-keygen -a -n && \
    cp /root/.abuild/*.pub /etc/apk/keys/ && \
    REPODEST=/tmp/out abuild -F -r


FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6
LABEL org.opencontainers.image.source=https://github.com/djhibee/betanin
WORKDIR /src

COPY --from=builder-mp3val /tmp/out/*/*.apk /pkgs/

# Dependencies are installed BEFORE the source is copied, so that editing any
# betanin source file does not invalidate this layer.
#
# It is worth being deliberate about: this is a ~400 MB install that compiles
# pillow, cryptography, gevent and friends against musl from source, because
# there are no manylinux wheels for Alpine. Upstream had `COPY . .` above it,
# which meant a one-character source edit paid the entire compile again.
#
# The stub package is what makes the split possible -- `pip install .` needs a
# package to exist before it will resolve the dependencies in pyproject.toml.
# It is overwritten by the real install further down.
#
# alpine's python is marked externally-managed (PEP 668). Nothing else in the
# image is installed from pip or depends on apk's python packages, so pip is
# allowed to install into the system site-packages.
#
# gcc >= 14 (alpine >= 3.21) made incompatible-pointer-types an error. aubio 0.4.9's
# C extension trips it (a const qualifier on numpy ufunc signatures); the CFLAGS
# below restore the old warning so the pinned aubio still builds unchanged.
#
# numpy 1.26.2 has no python 3.14 wheel, so it is compiled here against
# alpine's openblas, which therefore has to stay installed at runtime.
#
# patches/ holds the source fixes the pinned beets needs to run on
# python 3.14. Each is applied to the installed package with --forward, so the
# build fails loudly if one stops applying. See docs/FORK.md.

ENV UID=1000
ENV GID=1000
ENV UV_SYSTEM_PYTHON=1
ENV UV_BREAK_SYSTEM_PACKAGES=1
ENV UV_COMPILE_BYTECODE=1

COPY --from=ghcr.io/astral-sh/uv:0.11.2 /uv /usr/local/bin/uv

COPY requirements-docker.txt constraints.txt pyproject.toml version.txt README.md ./
COPY patches/ patches/
RUN mkdir -p betanin && touch betanin/__init__.py && \
    apk add --no-cache --upgrade --virtual=build-dependencies \
        build-base cmake libffi-dev openssl-dev python3-dev jpeg-dev libpng-dev \
        zlib-dev cargo llmdev openblas-dev libsndfile-dev && \
    apk add --no-cache --upgrade su-exec python3 libev chromaprint ffmpeg \
        gstreamer flac keyfinder-cli libsndfile mp3gain openblas && \
    apk add --no-cache --allow-untrusted /pkgs/* && \
    env CFLAGS="-Wno-error=incompatible-pointer-types" uv pip install --no-cache-dir . \
        --requirement requirements-docker.txt --constraint constraints.txt && \
    uv pip install --no-cache-dir soundfile --constraint constraints.txt && \
    # PATCH \
    site="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')" && \
    for p in patches/*.patch; do patch -d "$site" -p1 --forward -i "/src/$p" || exit 1; done && \
    apk del --purge build-dependencies && \
    rm -rf /pkgs ~/.cache betanin patches

# Only now the source, and a metadata-only reinstall over the stub.
COPY . .
COPY --from=builder-frontend /src/dist/ /src/betanin_client/dist/
RUN pip install --no-cache-dir --no-deps --force-reinstall . && rm -rf ~/.cache

VOLUME /b/.local/share/betanin/
VOLUME /b/.config/betanin/
VOLUME /b/.config/beets/

ENV HOME=/b
ENV PYTHONUNBUFFERED=1

ENTRYPOINT [ "/src/docker-entry" ]
