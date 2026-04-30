# Dist-over-mesh test node
# Builds an Erlang release that auto-connects to a relay and pings peers.
#
# Build: docker build -t dist-test:latest .
# Run:   docker run --network host \
#          -e MACULA_RELAY=https://relay-it-milan.macula.io:4433 \
#          -e PING_TARGETS=bob@nanode-stockholm \
#          dist-test:latest alice@nanode-milan DEMOCOOKIE

FROM erlang:27-alpine AS builder

RUN apk add --no-cache git curl bash build-base cmake rust cargo perl linux-headers

WORKDIR /app
COPY rebar.config ./
RUN rebar3 get-deps

# Hex package omits native/ — copy NIF source and symlink into dep tree
COPY native ./native
RUN ln -s /app/native _build/default/lib/macula/native

COPY src ./src
RUN rebar3 as prod release

# Runtime
FROM alpine:3.22
RUN apk add --no-cache ncurses-libs libstdc++ libgcc openssl ca-certificates

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/dist_test ./
COPY docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
