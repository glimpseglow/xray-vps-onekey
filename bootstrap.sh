#!/usr/bin/env bash
set -Eeuo pipefail
REPO="${XRAY_VPS_ONEKEY_REPO:-https://github.com/glimpseglow/xray-vps-onekey}"
BRANCH="${XRAY_VPS_ONEKEY_BRANCH:-main}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

command -v curl >/dev/null 2>&1 || { echo "需要 curl"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "需要 tar"; exit 1; }

curl -fsSL "${REPO}/archive/refs/heads/${BRANCH}.tar.gz" -o "${TMP_DIR}/src.tar.gz"
tar -xzf "${TMP_DIR}/src.tar.gz" -C "$TMP_DIR"
cd "${TMP_DIR}"/*
bash install.sh "$@"
