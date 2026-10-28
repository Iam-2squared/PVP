#!/usr/bin/env bash
# Local snapshot only. An off-VM backup is required for disaster recovery.
set -euo pipefail
umask 077
src="${1:-/var/lib/pvp/profiles/profiles.json}"
dst="${2:-/var/lib/pvp/backups}"
if [[ ! -s "$src" ]]; then
  echo "Profile file missing or empty: $src" >&2
  exit 1
fi
mkdir -p -- "$dst"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp "$dst/.profiles-$stamp.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
cp -- "$src" "$tmp"
python3 -m json.tool "$tmp" >/dev/null
chmod 600 -- "$tmp"
out="$dst/profiles-$stamp.json"
if [[ -e "$out" ]]; then
  echo "Backup already exists: $out" >&2
  exit 1
fi
mv -- "$tmp" "$out"
trap - EXIT
printf 'Local backup created: %s\n' "$out"
