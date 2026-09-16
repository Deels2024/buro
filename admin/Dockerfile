FROM alpine:3.20 AS release
RUN apk add --no-cache curl
COPY .git/ /git/
COPY scripts/read-release-sha.sh scripts/fetch-admin-release.sh /scripts/
ARG BUREAU_RELEASE_BASE_URL=https://github.com/Deels2024/buro/releases/download
RUN test ! -e /git/config && test ! -d /git/objects && \
    release="$(sh /scripts/read-release-sha.sh /git)" && \
    BUREAU_RELEASE_BASE_URL="$BUREAU_RELEASE_BASE_URL" sh /scripts/fetch-admin-release.sh "$release" /admin

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
COPY --from=release /admin ./
EXPOSE 3000
CMD ["node", "server.js"]
