#!/bin/bash
# Installs extra tooling (.NET SDK, GitHub CLI, Deno) and starts the Docker
# daemon for Claude Code on the web sessions.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# .NET SDK and GitHub CLI from the Ubuntu apt repositories.
missing_pkgs=()
command -v dotnet >/dev/null 2>&1 || missing_pkgs+=(dotnet-sdk-8.0)
command -v gh >/dev/null 2>&1 || missing_pkgs+=(gh)
if [ ${#missing_pkgs[@]} -gt 0 ]; then
  # Some third-party PPAs are blocked by the network policy; ignore their errors.
  apt-get update -qq || true
  apt-get install -y -qq "${missing_pkgs[@]}"
fi

# Deno via npm (deno.land is not reachable through the proxy).
if ! command -v deno >/dev/null 2>&1; then
  npm install -g deno
fi

# Docker daemon.
if command -v dockerd >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
  nohup dockerd >/tmp/dockerd.log 2>&1 &
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
  done
fi
