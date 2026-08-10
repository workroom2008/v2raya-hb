# ============================================================
# Multi-stage Dockerfile for v2rayA with fixed custom inbound UI
# Bug: modalCustomInbound.vue fetchOutbounds() used /outbound (singular)
#      instead of /outbounds (plural), causing empty dropdown
# Fix:  https://github.com/v2rayA/v2rayA/discussions/1907
# ============================================================

# Stage 1: Build frontend (Vue/Vite)
FROM --platform=$BUILDPLATFORM node:22-alpine AS frontend
WORKDIR /build/gui
COPY gui/package.json gui/yarn.lock ./
RUN corepack enable && yarn install --ignore-engines
COPY gui/ ./
RUN OUTPUT_DIR=/build/web yarn build

# Stage 2: Build Go binary with embedded frontend
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS backend
ARG TARGETOS=linux
ARG TARGETARCH=amd64
WORKDIR /build/service
COPY service/go.mod service/go.sum ./
RUN go mod download
COPY service/ ./
COPY --from=frontend /build/web ./server/router/web
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -tags "with_gvisor" \
    -ldflags "-X github.com/v2rayA/v2rayA/conf.Version=fix-ui -s -w" \
    -o /v2raya

# Stage 3: Final image - replace v2raya binary in official image
FROM mzz2017/v2raya:latest
COPY --from=backend /v2raya /usr/bin/v2raya
