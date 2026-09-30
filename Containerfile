FROM quay.io/hummingbird/go:1.27.1-builder@sha256:0682509f458d0ef449f2a3a95e067ecd8fc78bd0d89fc2d0f0cb5d2859908326 AS build

# Version is injected at build time; the container has no usable .git to derive
# it from (see `make container`). Defaults to "dev" for plain `podman build`.
ARG VERSION=dev

RUN dnf install -y make git && dnf clean all

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux make build VERSION="${VERSION}"

FROM quay.io/hummingbird/core-runtime:2.43@sha256:58f9030ce520821c61798d41ca52aa2b10ba5f20c49245f63ecffcfcaa3d464f

WORKDIR /app

COPY --from=build /app/forgejo-mcp .

ENTRYPOINT ["/app/forgejo-mcp"]
