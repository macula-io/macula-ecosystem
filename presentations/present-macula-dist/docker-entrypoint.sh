#!/bin/sh
# Entrypoint for dist-test container.
# Usage: docker run dist-test:latest <nodename> <cookie>
# e.g.:  docker run dist-test:latest alice@nanode-milan DEMOCOOKIE
set -eu

NODE_NAME="${1:-dist-test@localhost}"
COOKIE="${2:-DISTTEST}"

# Generate vm.args
cat > /app/releases/vm.args.generated <<EOF
-name ${NODE_NAME}
-setcookie ${COOKIE}
-proto_dist macula
-no_epmd
-kernel net_ticktime 120
+A 8
+P 262144
EOF

export VMARGS_PATH="/app/releases/vm.args.generated"
export MACULA_DIST_MODE=relay

exec /app/bin/dist_test foreground
