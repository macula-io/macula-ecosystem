#!/bin/bash
## Commands for the live demo portion of the presentation.
## Run these manually in two side-by-side terminals.
##
## LEFT terminal:  ssh root@172.232.219.239  (Milan, alpha)
## RIGHT terminal: ssh root@172.234.124.60   (Stockholm, beta)

## --- PRE-DEMO CLEANUP (run on both) ---
# docker stop dist-alpha dist-beta 2>/dev/null
# docker rm dist-alpha dist-beta 2>/dev/null

## --- RIGHT TERMINAL (Stockholm) — start beta first ---

docker run --network host \
  -e RELAY_URL=https://relay-de-munich.macula.io:4433 \
  -e NODE_IDENTITY=dist-beta \
  dist-test:latest beta@172.234.124.60 DISTMESHTEST

## Wait for: [dist_test] Distribution relay READY

## --- LEFT TERMINAL (Milan) — start alpha with ping ---

docker run --network host \
  -e RELAY_URL=https://relay-de-munich.macula.io:4433 \
  -e NODE_IDENTITY=dist-alpha \
  -e PING_TARGET='beta@172.234.124.60' \
  dist-test:latest alpha@172.232.219.239 DISTMESHTEST

## Expected output:
## [dist_test] PING 'beta@172.234.124.60' → pong
## [dist_test] CONNECTED! Nodes: ['beta@172.234.124.60']
