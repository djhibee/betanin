# Base images are digest-pinned. Tags move; digests do not, and the point of
# this fork is that a build in six months produces the same image as a build
# today. See docs/FORK.md.
#
# Note this pins the OS layer going forward, not backwards: the apk packages
# here are alpine 3.18 as of the pin date, which is newer than those in the
# image originally built in March 2026. What is reproduced exactly is the
# Python dependency tree, which is where beets and all of our match tuning
# live. See requirements-docker.txt.

FROM node:16-alpine3.17@sha256:bbc110afcd56dea9d27969ce1c3585aac53192ad14b364b6c5cb1f25a144ad9f AS builder-frontend
WORKDIR /src
COPY betanin_client/ .
RUN npm install && \
    PRODUCTION=true npm run-script build


FROM alpine:3.18@sha256:de0eb0b3f2a47ba1eb89389859a9bd88b28e82f5826b6969ad604979713c2d4f AS builder-mp3gain
WORKDIR /tmp
COPY alpine/mp3gain/APKBUILD .
RUN apk update && \
    apk add --no-cache abuild && \
    abuild-keygen -a -n && \
    cp /root/.abuild/*.pub /etc/apk/keys/ && \
    REPODEST=/tmp/out abuild -F -r


FROM alpine:3.18@sha256:de0eb0b3f2a47ba1eb89389859a9bd88b28e82f5826b6969ad604979713c2d4f AS builder-mp3val
WORKDIR /tmp
COPY alpine/mp3val/APKBUILD .
RUN apk update && \
    apk add --no-cache abuild && \
    abuild-keygen -a -n && \
    cp /root/.abuild/*.pub /etc/apk/keys/ && \
    REPODEST=/tmp/out abuild -F -r


FROM alpine:3.18@sha256:de0eb0b3f2a47ba1eb89389859a9bd88b28e82f5826b6969ad604979713c2d4f
LABEL org.opencontainers.image.source https://github.com/aglowinthefield/betanin
WORKDIR /src

COPY --from=builder-mp3gain /tmp/out/*/*.apk /pkgs/
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
COPY requirements-docker.txt constraints.txt pyproject.toml version.txt README.md ./
RUN mkdir -p betanin && touch betanin/__init__.py && \
    apk add --no-cache --upgrade --virtual=build-dependencies \
        build-base cmake libffi-dev openssl-dev python3-dev jpeg-dev libpng-dev \
        zlib-dev cargo llvm14-dev openblas openblas-dev libsndfile-dev && \
    apk add --no-cache --upgrade su-exec python3 py-pip libev chromaprint ffmpeg \
        gstreamer flac keyfinder-cli libsndfile && \
    apk add --no-cache --allow-untrusted /pkgs/* && \
    env LLVM_CONFIG="$(which llvm14-config)" pip install --no-cache-dir . \
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
