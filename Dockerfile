# ============================================================
# Multi-stage Dockerfile for v2rayA with fixed custom inbound UI
# Uses official v2rayA prebuilt core (v2raya_core)
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
RUN V2RAYA_VERSION=$(wget -qO- https://api.github.com/repos/v2rayA/v2rayA/releases/latest | sed -n 's/.*"tag_name": *"v\(.*\)".*/\1/p' | head -n1) && \
    echo "Building with version ${V2RAYA_VERSION}" && \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -tags "with_gvisor" \
    -ldflags "-X github.com/v2rayA/v2rayA/conf.Version=${V2RAYA_VERSION} -s -w" \
    -o /v2raya

# Stage 3: Final image
FROM alpine:latest

RUN apk add --no-cache iptables iptables-legacy nftables tzdata curl ca-certificates

COPY --from=backend /v2raya /usr/bin/v2raya

# Download v2raya_core from official v2rayA releases
# TARGETARCH is automatically available from BuildKit
ARG TARGETARCH
RUN apk add --no-cache wget jq >/dev/null  \
    && V2RAYA_VERSION=$(wget -qO- https://api.github.com/repos/v2rayA/v2rayA/releases/latest | jq -r .tag_name | sed 's/^v//') && \
    echo "Target arch: ${TARGETARCH}, core version: ${V2RAYA_VERSION}" && \
    case "${TARGETARCH}" in \
      amd64)  V2RAYA_ARCH="x64" ;; \
      arm64)  V2RAYA_ARCH="arm64" ;; \
      arm/v7) V2RAYA_ARCH="armv7" ;; \
      riscv64) V2RAYA_ARCH="riscv64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "Downloading v2raya_core_linux_${V2RAYA_ARCH}_${V2RAYA_VERSION}..." && \
    curl -fsSL -o /usr/bin/v2raya_core \
      "https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya_core_linux_${V2RAYA_ARCH}_${V2RAYA_VERSION}" && \
    chmod +x /usr/bin/v2raya_core && \
    echo "v2raya_core ${V2RAYA_VERSION} downloaded successfully"

COPY install/docker/iptables.sh /usr/local/bin/iptables
COPY install/docker/ip6tables.sh /usr/local/bin/ip6tables
RUN ln -sf /usr/local/bin/iptables /usr/local/bin/iptables-nft && \
    ln -sf /usr/local/bin/ip6tables /usr/local/bin/ip6tables-nft && \
    ln -sf /usr/local/bin/iptables /usr/local/bin/iptables-legacy && \
    ln -sf /usr/local/bin/ip6tables /usr/local/bin/ip6tables-legacy

RUN mkdir -p /usr/share/v2raya && \
    apk add --no-cache jq >/dev/null && \
    curl -fsSL -o /usr/share/v2raya/geosite.dat https://raw.githubusercontent.com/v2rayA/dist-v2ray-rules-dat/master/geosite.dat && \
    curl -fsSL -o /usr/share/v2raya/geoip.dat https://raw.githubusercontent.com/v2rayA/dist-v2ray-rules-dat/master/geoip.dat && \
    curl -fsSL -o /usr/share/v2raya/LoyalsoldierSite.dat https://raw.githubusercontent.com/v2rayA/dist-v2ray-rules-dat/master/geosite.dat && \
    GFWLIST_TAG=$(wget -qO- https://api.github.com/repos/v2rayA/dist-v2ray-rules-dat/tags | jq -r '.[0].name') && \
    GFWLIST_DATE=$(echo "$GFWLIST_TAG" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$/\1-\2-\3 \4:\5/') && \
    echo "geo data tag: ${GFWLIST_TAG} (${GFWLIST_DATE} UTC)" && \
    date -u -d "${GFWLIST_DATE}" "+%s" >/dev/null && \
    touch -m -d "${GFWLIST_DATE} +0000" /usr/share/v2raya/*.dat

EXPOSE 2017
VOLUME /etc/v2raya
ENTRYPOINT ["v2raya"]
