# ============================================================
# v2rayA 镜像（跟随上游最新 release，含 pre-release）
# 直接使用官方预编译的 v2raya + v2raya_core，二者版本严格一致
# ============================================================

FROM alpine:latest

ARG TARGETARCH
ARG V2RAYA_VERSION=""

RUN apk add --no-cache \
      iptables iptables-legacy nftables tzdata \
      curl ca-certificates wget jq

# V2RAYA_VERSION 由 CI 传参指定（可作缓存失效），为空则取上游最新 release（含 pre-release）
RUN set -eux; \
    if [ -z "${V2RAYA_VERSION}" ]; then \
      V2RAYA_VERSION=$(wget -qO- "https://api.github.com/repos/v2rayA/v2rayA/releases?per_page=30" \
        | jq -r '[.[] | select(.draft == false)][0].tag_name' | sed 's/^v//'); \
    else \
      V2RAYA_VERSION=$(echo "${V2RAYA_VERSION}" | sed 's/^v//'); \
    fi; \
    case "${TARGETARCH}" in \
      amd64)   V2RAYA_ARCH="x64" ;; \
      arm64)   V2RAYA_ARCH="arm64" ;; \
      arm)     V2RAYA_ARCH="armv7" ;; \
      riscv64) V2RAYA_ARCH="riscv64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    echo "v2raya version: ${V2RAYA_VERSION}, arch: ${V2RAYA_ARCH}"; \
    curl -fsSL -o /usr/bin/v2raya \
      "https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya_linux_${V2RAYA_ARCH}_${V2RAYA_VERSION}"; \
    curl -fsSL -o /usr/bin/v2raya_core \
      "https://github.com/v2rayA/v2rayA/releases/download/v${V2RAYA_VERSION}/v2raya_core_linux_${V2RAYA_ARCH}_${V2RAYA_VERSION}"; \
    chmod +x /usr/bin/v2raya /usr/bin/v2raya_core; \
    echo "v2raya ${V2RAYA_VERSION} + v2raya_core ${V2RAYA_VERSION} installed"

COPY install/docker/iptables.sh /usr/local/bin/iptables
COPY install/docker/ip6tables.sh /usr/local/bin/ip6tables
RUN ln -sf /usr/local/bin/iptables /usr/local/bin/iptables-nft && \
    ln -sf /usr/local/bin/ip6tables /usr/local/bin/ip6tables-nft && \
    ln -sf /usr/local/bin/iptables /usr/local/bin/iptables-legacy && \
    ln -sf /usr/local/bin/ip6tables /usr/local/bin/ip6tables-legacy

# geo 数据取 v2rayA 官方最新，mtime 对齐最新 tag（否则 v2rayA 误判“已是最新”而不更新）
RUN mkdir -p /usr/share/v2raya && \
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
