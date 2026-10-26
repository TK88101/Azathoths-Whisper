#!/bin/zsh
# MD Vinyl 素材只放本機（sprint-5-detail.md D1、§4.9；使用者 2026-10-19 拍板）：
# 從來源目錄複製 S5 用到的圖到 gitignore 的 Resources/VinylAssets.local/（WebP 以 sips 轉 PNG），
# 並重寫 Scripts/vinyl_asset_hashes.txt（原檔與轉出檔的 SHA-256；只有雜湊、不含素材，供 echo_gate E9 擋改名誤加）。
# 用法（在 YogSothothsEcho/ 下）：Scripts/fetch_vinyl_assets.sh <來源目錄>（必填）
set -euo pipefail
SRC=${1:?用法：Scripts/fetch_vinyl_assets.sh <素材來源目錄>}
HERE=${0:A:h}
DEST="$HERE/../Resources/VinylAssets.local"
HASHES="$HERE/vinyl_asset_hashes.txt"
NAMES=(
  vinyl_player_vinyl_record_colorful_base vinyl_player_vinyl_record_colorful_noise
  vinyl_player_vinyl_record_colorful_pattern1 vinyl_player_vinyl_record_colorful_pattern2
  vinyl_player_vinyl_record_colorful_marble vinyl_player_vinyl_center
  vinyl_player_arm_black vinyl_player_base_blur vinyl_player_blur_bg
  vinyl_player_vinyl_preview_classic vinyl_player_vinyl_preview_colored_base
  vinyl_player_vinyl_preview_splash_pattern vinyl_player_vinyl_preview_marble
)
[[ -d "$SRC" ]] || { print -u2 "找不到來源目錄：$SRC"; exit 1; }
mkdir -p "$DEST"
{
  print "# MD Vinyl 素材的 SHA-256（fetch_vinyl_assets.sh 產生；E9 用，勿手改）"
  for name in $NAMES; do
    src=("$SRC/$name".(png|webp)(N))
    [[ ${#src} -eq 1 ]] || { print -u2 "缺素材或重複：$name"; exit 1; }
    out="$DEST/$name.png"
    if [[ $src[1] == *.webp ]]; then
      sips -s format png "$src[1]" --out "$out" >/dev/null
    else
      cp "$src[1]" "$out"
    fi
    shasum -a 256 "$src[1]" | cut -d' ' -f1
    shasum -a 256 "$out" | cut -d' ' -f1
  done | sort -u
} > "$HASHES.tmp"
mv "$HASHES.tmp" "$HASHES"
print "已複製 ${#NAMES} 個素材到 $DEST"
