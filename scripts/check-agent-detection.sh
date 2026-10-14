#!/bin/bash
# Why Owlet cannot find a local agent CLI on this machine. Run it on the machine that fails,
# then paste the whole output back. Usage: bash check-agent-detection.sh [name]   (default: claude)
set -u
NAME="${1:-claude}"

echo "=== 1. installed Owlet versions ==="
for app in /Applications/Owlet.app "$HOME/Applications/Owlet.app"; do
    if [ -d "$app" ]; then
        printf '%s -> %s\n' "$app" "$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)"
    fi
done

echo "=== 2. well-known install locations ==="
for p in "$HOME/.local/bin/$NAME" "$HOME/.claude/local/$NAME" "/opt/homebrew/bin/$NAME" "/usr/local/bin/$NAME"; do
    if [ -e "$p" ]; then
        printf '%-42s present  executable=%s  -> %s\n' "$p" \
            "$([ -x "$p" ] && echo yes || echo no)" "$(readlink "$p" 2>/dev/null || echo -)"
    else
        printf '%-42s absent\n' "$p"
    fi
done

echo "=== 3. the probe under three environments (byte-exact) ==="
probe() {
    local label="$1"; shift
    local out code
    out=$(env "$@" /bin/zsh -lc "command -v $NAME" 2>/tmp/owlet-probe-err); code=$?
    printf '%-14s exit=%s  stdout_bytes=%s  stderr=%s\n' "$label" "$code" \
        "$(printf '%s' "$out" | wc -c | tr -d ' ')" "$(head -c 200 /tmp/owlet-probe-err | tr '\n' ' ')"
    printf '%s' "$out" | od -c | head -3
}
probe inherited
probe minimal      PATH=/usr/bin:/bin:/usr/sbin:/sbin
probe minimal+brew PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin

echo "=== 4. running it directly ==="
"$HOME/.local/bin/$NAME" --version 2>&1 | head -2

echo "=== 5. PATH lines in the shell startup files ==="
grep -Hn "PATH" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin" 2>/dev/null | head -20

echo "=== 6. which tools exist under the minimal PATH ==="
env PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c 'for t in mise fnm asdf brew node npm; do printf "%s=%s " "$t" "$(command -v $t 2>/dev/null || echo -)"; done; echo'

echo "=== 7. system path sources ==="
ls /etc/paths.d 2>/dev/null
cat /etc/paths 2>/dev/null
