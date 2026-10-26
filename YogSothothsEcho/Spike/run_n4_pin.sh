#!/bin/bash
# N4 診斷補充（s0-offline-2026-10-15.md T4）：產生測試用自簽憑證 → yse-spike n4-pin → 刪除憑證與私鑰。
# 用法：./run_n4_pin.sh <yse-spike 路徑>（S0_RESULTS_DIR 有設時結果落盤）。不碰 Music、不碰 Keychain。
set -euo pipefail
BIN="${1:?需要 yse-spike 路徑}"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT INT TERM HUP
for name in server client other; do
    openssl ecparam -name prime256v1 -genkey -noout -out "$DIR/$name.key" 2>/dev/null
    openssl req -new -x509 -key "$DIR/$name.key" -out "$DIR/$name.crt" -days 2 -subj "/CN=yse-n4-$name" 2>/dev/null
    openssl pkcs12 -export -inkey "$DIR/$name.key" -in "$DIR/$name.crt" -out "$DIR/$name.p12" \
        -passout pass:yse-test -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
done
YSE_PIN_DIR="$DIR" "$BIN" n4-pin
