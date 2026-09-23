#!/bin/bash
# queue_spike 的靜態閘門（計劃 §8 S0、AC9 ③ 的 spike 版，比 production 更嚴：零 setter、不許 KVC 讀取）。
# 主防線是 queue_spike 啟動時的執行期自檢（協議選擇器白名單）；本腳本補「不經協議」的路徑。
# 用法：spike_gate.sh <檔案>   或   printf '...' | spike_gate.sh -   （負對照）
# 命中任一禁止模式 → 印出位置並以 1 退出。
set -euo pipefail
src="${1:--}"
content=$(cat "$src")
fail=0
check() {
    local label="$1" pattern="$2" hits
    hits=$(printf '%s\n' "$content" | grep -nE "$pattern" || true)
    if [[ -n "$hits" ]]; then
        printf '%s\n' "$hits" | sed "s/^/VIOLATION [$label] line /" >&2
        fail=1
    fi
}
check other-ae-channel 'NSAppleScript|NSUserAppleScriptTask|OSAScript|osascript|\bAESend\(|NSAppleEventDescriptor\(eventClass|sendEvent\(options:|MediaRemote|NX_KEYTYPE|import +(OSAKit|Carbon)'
check dynamic-dispatch 'perform\(|NSSelectorFromString|Selector\(\(|setValue\(|makeObjectsPerform|byApplying:[^)]*with:|\.(add|insert|remove|replace)(Object)?\('
check kvc 'value\(forKey:'
check setter-decl '\{ *get +set *\}|func +set[A-Z]'
exit $fail
