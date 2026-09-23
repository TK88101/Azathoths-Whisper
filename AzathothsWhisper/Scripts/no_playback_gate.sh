#!/bin/bash
# 無播控閘門（計劃 AC9 ③、AC8c）：補「不經 Music @objc 協議」的路徑。
# 主防線是執行期選擇器白名單（Tests/Services/MusicSelectorAllowListTests.swift）；本腳本擋的是：
#   R1 全部 target 目錄＋spike：其他送 Apple Event／模擬按鍵的管道
#   R2 `import ScriptingBridge` 只許出現在 Music client 與 spike
#   R3 Music client：動態派送、KVC 寫入、元素增刪；KVC 讀取的 key 只許 rawData
#   R4 Queue.dat／History.dat 讀取模組：任何寫入／移動／刪除 API
# 用法：
#   Scripts/no_playback_gate.sh                     掃整個專案（在 AzathothsWhisper/ 下執行）
#   Scripts/no_playback_gate.sh --stdin <路徑>      把 stdin 當成該路徑的檔案檢查（負對照用）
# 任一違規 → 印出位置、退出 1。行內 // 註解不列入比對。
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET_DIRS=(App Features Services Infra UI Scripts/spike)
SB_ALLOWED='^(Services/Music/MusicAppleEventsClient\.swift|Scripts/spike/[^/]+\.swift)$'
SB_FILE='^Services/Music/MusicAppleEventsClient\.swift$'
READ_ONLY_FILES='^Services/Music/(QueueFileSource|QueueSnapshot|HistorySnapshot)\.swift$'

R1='NSAppleScript|NSUserAppleScriptTask|OSAScript|osascript|\bAESend\(|NSAppleEventDescriptor\(eventClass|sendEvent\(options:|MediaRemote|NX_KEYTYPE|^[[:space:]]*import[[:space:]]+(OSAKit|Carbon)\b'
R3='perform\(|NSSelectorFromString|Selector\(\(|setValue\(|makeObjectsPerform|byApplying:[^)]*with:|\.(add|insert|remove|replace)(Object)?\('
R4='\.write\(|createFile|removeItem|moveItem|copyItem|replaceItem|setAttributes|FileHandle\(forWriting|FileHandle\(forUpdating|\.truncate\(|O_(WRONLY|RDWR|CREAT)'

status=0
report() { printf 'VIOLATION [%s] %s: %s\n' "$1" "$2" "$3" >&2; status=1; }

check() {   # $1＝相對路徑，stdin＝內容
    local path="$1" content line hits
    content=$(sed -E 's#([^:"])//.*$#\1#; s#^//.*$##')
    while IFS= read -r line; do report R1 "$path" "$line"; done < <(grep -nE "$R1" <<<"$content" || true)
    if grep -qE '^[[:space:]]*import[[:space:]]+ScriptingBridge\b' <<<"$content" && ! [[ "$path" =~ $SB_ALLOWED ]]; then
        report R2 "$path" "import ScriptingBridge 只許出現在 Music client 與 spike"
    fi
    # Music client 一律檢查（不論內容寫了什麼）；其他檔案只要 import ScriptingBridge 也檢查
    if [[ "$path" =~ $SB_FILE ]] || grep -qE '^[[:space:]]*import[[:space:]]+ScriptingBridge\b' <<<"$content"; then
        while IFS= read -r line; do report R3 "$path" "$line"; done < <(grep -nE "$R3" <<<"$content" || true)
        while IFS= read -r line; do report R3-kvc "$path" "$line"; done \
            < <(grep -noE 'value\(forKey:[[:space:]]*"[^"]*"' <<<"$content" | grep -vE '"rawData"$' || true)
    fi
    if [[ "$path" =~ $READ_ONLY_FILES ]]; then
        while IFS= read -r line; do report R4 "$path" "$line"; done < <(grep -nE "$R4" <<<"$content" || true)
    fi
}

if [[ "${1:-}" == "--stdin" ]]; then
    check "${2:?需要路徑}"
    exit $status
fi

while IFS= read -r file; do
    check "$file" < "$file"
done < <(find "${TARGET_DIRS[@]}" -name '*.swift' -type f | sort)
exit $status
