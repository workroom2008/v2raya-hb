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
    -ldflags "-X github.com/v2rayA/v2rayA/conf.Version=2.4.10 -s -w" \
    -o /v2raya

# Stage 3: Build v2raya-core (merged xray-core + custom protocols)
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS core
ARG TARGETOS=linux
ARG TARGETARCH=amd64
WORKDIR /build/core
COPY core/go.mod core/go.sum ./
RUN go mod download
COPY core/ ./
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath \
    -ldflags "-X main.Version=2.4.10 -s -w" \
    -o /v2raya_core ./main

# Stage 4: Final image
FROM alpine:latest
RUN apk add --no-cache iptables iptables-legacy nftables tzdata

# Copy binaries from builder stages
COPY --from=backend /v2raya /usr/bin/v2raya
COPY --from=core /v2raya_core /usr/bin/v2raya_core

# Copy iptables helper scripts
COPY install/docker/iptables.sh /usr/local/bin/iptables
COPY install/docker/ip6tables.sh /usr/local/bin/ip6tables
RUN ln -sf /usr/local/bin/iptables /usr/local/bin/iptables-nft && \
    ln -sf /usr/local/bin/ip6tables /usr/local/bin/ip6tables-nft && \
    ln -sf /usr/local/bin/iptables /usr/local/bin/iptables-legacy && \
    ln -sf /usr/local/bin/ip6tables /usr/local/bin/ip6tables-legacy

# Download geo data files from v2rayA official repository
RUN mkdir -p /usr/share/v2raya && \
    wget -O /usr/share/v2raya/geosite.dat https://raw.githubusercontent.com/v2rayA/dist-v2ray-rules-dat/master/geosite.dat && \
    wget -O /usr/share/v2raya/geoip.dat https://raw.githubusercontent.com/v2rayA/dist-v2ray-rules-dat/master/geoip.dat && \
    wget -O /usr/share/v2raya/LoyalsoldierSite.dat https://raw.githubusercontent.com/v2rayA/dist-v2ray-rules-dat/master/geosite.dat

EXPOSE 2017
VOLUME /etc/v2raya
ENTRYPOINT ["v2raya"]
