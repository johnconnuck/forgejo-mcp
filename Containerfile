FROM quay.io/hummingbird/go:1.27.1-builder@sha256:ebc0a02e3b1b8fae63a4206a76eeff84ef5c0520fbeb5f7666e6adc5a429c924 AS build

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
