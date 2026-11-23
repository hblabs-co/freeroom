# syntax=docker.io/docker/dockerfile:1
# freeroom.hblabs.co: one static Go binary, everything go:embedded (pages, locales, static files,
# and the HB Labs UI kit from github.com/hblabs-co/kit/web). Build from this directory:
#   docker build -t freeroom-site --build-arg BUILD_VERSION=$(cat VERSION) .
ARG GO_VERSION=1.26.2

FROM golang:${GO_VERSION}-alpine AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/site .

FROM gcr.io/distroless/static-debian12:nonroot
ARG BUILD_TIME=unknown
ARG BUILD_VERSION=unknown
# Read by github.com/hblabs-co/kit/core/system and logged once at boot.
ENV HB_BUILD_TIME=${BUILD_TIME} \
    HB_BUILD_VERSION=${BUILD_VERSION} \
    HB_PORT=8080 \
    TZ=Europe/Berlin \
    HB_LOG_FORMAT=json \
    HB_ENV=prod
COPY --from=build /out/site /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
