# syntax=docker/dockerfile:1

# ---- build stage ----
FROM node:20-bookworm-slim AS build
WORKDIR /app/backend
COPY backend/package.json backend/package-lock.json ./
RUN npm ci
COPY backend/tsconfig.json ./
COPY backend/src ./src
RUN npm run build

# ---- runtime stage ----
# node:20-bookworm-slim (glibc), NOT -alpine: ffmpeg-static/ffprobe-static ship
# prebuilt binaries linked against glibc and silently fail to exec under musl.
FROM node:20-bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    DATA_DIR=/data

COPY backend/package.json backend/package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/backend/dist ./dist
COPY web ./dist/static

RUN mkdir -p /data/blobs /data/db

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --retries=5 \
  CMD wget --spider -q http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
