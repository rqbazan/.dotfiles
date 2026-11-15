#!/bin/sh
# Claude Code status line: model │ effort │ ctx bar │ 5h limit │ agents (optional).
# Reads the session JSON on stdin. POSIX sh, needs jq.
input=$(cat)

# One jq call; fields joined by US (0x1f) so empty ones keep their place in `read`.
us=$(printf '\037')
fields=$(printf '%s' "$input" | jq -r '[
  (.model.display_name // "?"),
  (.effort.level // ""),
  ((.context_window.used_percentage // 0) | floor),
  ((.rate_limits.five_hour.used_percentage // "") | if . == "" then "" else floor end),
  (.session_id // "")
] | map(tostring) | join("\u001f")' 2>/dev/null)
IFS="$us" read -r model effort ctx five sid <<EOT
$fields
EOT

case "$ctx"  in ''|*[!0-9]*) ctx=0 ;; esac
case "$five" in ''|*[!0-9]*) five="" ;; esac
[ "$ctx" -gt 100 ] && ctx=100
[ -n "$five" ] && [ "$five" -gt 100 ] && five=100

esc=$(printf '\033')
dim="${esc}[2m"; bold="${esc}[1m"; red="${esc}[31m"; yel="${esc}[33m"; grn="${esc}[32m"; rst="${esc}[0m"
sep=" ${dim}│${rst} "

# colour by threshold: green < 70, yellow < 90, red otherwise
tone() { if [ "$1" -ge 90 ]; then printf '%s' "$red"; elif [ "$1" -ge 70 ]; then printf '%s' "$yel"; else printf '%s' "$grn"; fi; }

line="${bold}${model:-?}${rst}"

if [ -n "$effort" ]; then
  case "$effort" in
    xhigh|max) ec="${bold}${red}" ;;
    high)      ec="${yel}" ;;
    *)         ec="" ;;
  esac
  line="${line}${sep}${dim}effort${rst} ${ec}${effort}${rst}"
fi

filled=$((ctx * 10 / 100)); i=0; bar=""
while [ "$i" -lt 10 ]; do
  if [ "$i" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
  i=$((i + 1))
done
line="${line}${sep}${dim}ctx${rst} $(tone "$ctx")${bar} ${ctx}%${rst}"

[ -n "$five" ] && line="${line}${sep}${dim}5h${rst} $(tone "$five")${five}%${rst}"

# Optional: a mod can keep the running-agent count in this file; absent → no segment.
agents_file="$HOME/.claude/statusline/agents-${sid}"
if [ -n "$sid" ] && [ -r "$agents_file" ]; then
  n=$(head -c 8 "$agents_file" | tr -dc '0-9')
  if [ -n "$n" ]; then
    [ "$n" -eq 1 ] && word=agent || word=agents
    line="${line}${sep}${dim}◇${rst} ${n} ${word}"
  fi
fi

printf '%s' "$line"
