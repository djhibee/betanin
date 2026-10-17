# Base images are digest-pinned. Tags move; digests do not, and the point of
# this fork is that a build in six months produces the same image as a build
# today. See docs/FORK.md.
#
# Note this pins the OS layer going forward, not backwards: the apk packages
# here are alpine 3.22 as of the pin date (moved off 3.18, which is EOL; 3.22
# keeps python 3.12 and chromaprint 1.5.1). What is reproduced exactly is the
# Python dependency tree, which is where beets and all of our match tuning
# live. See requirements-docker.txt.

# node 22 (v22.23.3, alpine 3.24). The frontend is built with webpack 4, which
# needs the legacy OpenSSL provider on node >= 17.
FROM node:22-alpine@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS builder-frontend
WORKDIR /src
COPY betanin_client/ .
RUN npm install && \
    NODE_OPTIONS=--openssl-legacy-provider PRODUCTION=true npm run-script build


FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS builder-mp3val
WORKDIR /tmp
COPY alpine/mp3val/APKBUILD .
RUN apk update && \
    apk add --no-cache abuild && \
    abuild-keygen -a -n && \
    cp /root/.abuild/*.pub /etc/apk/keys/ && \
    REPODEST=/tmp/out abuild -F -r


FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
LABEL org.opencontainers.image.source=https://github.com/aglowinthefield/betanin
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
# gcc 14 (alpine >= 3.21) made incompatible-pointer-types an error. aubio 0.4.9's
# C extension trips it (a const qualifier on numpy ufunc signatures); the CFLAGS
# below restore gcc 13's warning so the pinned aubio still builds unchanged.
COPY requirements-docker.txt constraints.txt pyproject.toml version.txt README.md ./
ENV PIP_BREAK_SYSTEM_PACKAGES=1
RUN mkdir -p betanin && touch betanin/__init__.py && \
    apk add --no-cache --upgrade --virtual=build-dependencies \
        build-base cmake libffi-dev openssl-dev python3-dev jpeg-dev libpng-dev \
        zlib-dev cargo openblas openblas-dev libsndfile-dev && \
    apk add --no-cache --upgrade su-exec python3 py-pip libev chromaprint ffmpeg \
        gstreamer flac keyfinder-cli libsndfile mp3gain && \
    apk add --no-cache --allow-untrusted /pkgs/* && \
    env CFLAGS="-Wno-error=incompatible-pointer-types" pip install --no-cache-dir . \
        --requirement requirements-docker.txt --constraint constraints.txt && \
    pip install --no-cache-dir soundfile --constraint constraints.txt && \
    apk del --purge build-dependencies && \
    rm -rf /pkgs ~/.cache betanin

# Only now the source, and a metadata-only reinstall over the stub.
COPY . .
COPY --from=builder-frontend /src/dist/ /src/betanin_client/dist/
RUN pip install --no-cache-dir --no-deps --force-reinstall . && rm -rf ~/.cache

VOLUME /b/.local/share/betanin/
VOLUME /b/.config/betanin/
VOLUME /b/.config/beets/

ENV UID=1000
ENV GID=1000
ENV HOME=/b
ENV PYTHONUNBUFFERED=1

ENTRYPOINT [ "/src/docker-entry" ]
