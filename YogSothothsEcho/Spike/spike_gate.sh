#!/bin/bash
# S0 量測工具的靜態閘門（docs/plans/2026-10-14-yse/sprint-0-detail.md §4.4）。
# 主防線是 yse-spike 啟動時的選擇器白名單自檢；本腳本補「不經協議」的路徑與檔案存取的隔離。
# 用法：
#   ./spike_gate.sh                     掃 Sources/ 下全部 .swift
#   ./spike_gate.sh --stdin <相對路徑>   把 stdin 當成該路徑的檔案檢查（負對照用）
# 任一違規 → 印出位置、退出 1。// 註解不列入比對。
set -euo pipefail
cd "$(dirname "$0")"

BRIDGE_FILE='^Sources/yse-spike/MusicBridge\.swift$'
READER_FILE='^Sources/yse-spike/MusicFileReader\.swift$'
WRITER_FILE='^Sources/yse-spike/ResultWriter\.swift$'
RUNNER_FILE='^Sources/yse-spike/ShortcutRunner\.swift$'
# F-P-01 ③：捷徑是協議外的另一條 Music 控制路徑，只准 ShortcutRunner.swift 呼叫；它只准寫、刪自己的暫存輸入檔 inputFile
#（2026-10-15 preflight 實證 `--input-path /dev/stdin` 讀不到內容，改用暫存檔）
RUNNER_OWN_FILE='input\.write\(to: inputFile\)|removeItem\(at: inputFile\)'
ALLOWED_SETTERS='^(setPlayerPosition|setCurrentAirPlayDevices)$'

AE_CHANNEL='NSAppleScript|NSUserAppleScriptTask|OSAScript|osascript|\bAESend\(|NSAppleEventDescriptor\(eventClass|sendEvent\(options:|MediaRemote|NX_KEYTYPE|CGEventPost|CGEvent\(keyboardEventSource|^[[:space:]]*import[[:space:]]+(OSAKit|Carbon)\b'
DYNAMIC='perform\(|NSSelectorFromString|Selector\(\(|setValue\(|makeObjectsPerform|byApplying:[^)]*with:|\.(add|insert|remove|replace)(Object)?\('
FILE_WRITE='\.write\(|createFile|removeItem|moveItem|copyItem|replaceItem|setAttributes|FileHandle\(forWriting|FileHandle\(forUpdating|\.truncate\(|O_(WRONLY|RDWR|CREAT)|\bopen\(|\brename\(|\bunlink\(|trashItem|\bfopen\('
# 繞過協定白名單的管道（security review M1 實測）：任意物件動態呼叫、元素整批刪除、直接造腳本類別、底層訊息派送
BRIDGE_ESCAPE='AnyObject|removeAll|exchange|objc_msgSend|class_getMethodImplementation|method\(for:|forScriptingClass'

status=0
report() { printf 'VIOLATION [%s] %s: %s\n' "$1" "$2" "$3" >&2; status=1; }

each_hit() {   # $1＝標籤 $2＝路徑 $3＝pattern $4＝內容 [$5＝grep 旗標]
    local line
    while IFS= read -r line; do report "$1" "$2" "$line"; done \
        < <(grep -n${5:-} -E "$3" <<<"$4" || true)
}

check() {   # $1＝相對路徑，stdin＝內容
    local path="$1" content name
    content=$(sed -E 's#([^:"])//.*$#\1#; s#^[[:space:]]*//.*$##')

    each_hit other-ae-channel "$path" "$AE_CHANNEL" "$content"
    each_hit dynamic-dispatch "$path" "$DYNAMIC" "$content"
    each_hit bridge-escape "$path" "$BRIDGE_ESCAPE" "$content"
    each_hit kvc "$path" 'value\(forKey:' "$content"
    each_hit setter-decl "$path" '\{[[:space:]]*get[[:space:]]+set[[:space:]]*\}' "$content"
    while IFS= read -r name; do
        [[ "$name" =~ $ALLOWED_SETTERS ]] || report setter-decl "$path" "func $name 不在允許清單"
    done < <(grep -oE 'func[[:space:]]+set[A-Z][A-Za-z0-9]*' <<<"$content" | sed -E 's/^func[[:space:]]+//' || true)

    if ! [[ "$path" =~ $BRIDGE_FILE ]]; then
        each_hit scripting-bridge "$path" '^[[:space:]]*import[[:space:]]+ScriptingBridge\b' "$content"
    fi
    if ! [[ "$path" =~ $READER_FILE ]]; then
        # 字串字面量裡出現 Queue／History 就算（擋 "Queue" + ".dat" 這種拼接）
        each_hit music-files "$path" '"[^"]*(Queue|History)' "$content"
    fi
    if ! [[ "$path" =~ $RUNNER_FILE ]]; then
        each_hit shortcut-runner "$path" '"[^"]*shortcuts' "$content"
    fi
    if [[ "$path" =~ $WRITER_FILE ]]; then
        each_hit writer-scope "$path" 'music|queue|history' "$content" i
    elif [[ "$path" =~ $RUNNER_FILE ]]; then
        each_hit file-write "$path" "$FILE_WRITE" "$(sed -E "s/$RUNNER_OWN_FILE//g" <<<"$content")"
    else
        each_hit file-write "$path" "$FILE_WRITE" "$content"
    fi
}

if [[ "${1:-}" == "--stdin" ]]; then
    check "${2:?需要路徑}"
    exit $status
fi

while IFS= read -r file; do
    check "$file" < "$file"
done < <(find Sources -name '*.swift' -type f | sort)
exit $status
