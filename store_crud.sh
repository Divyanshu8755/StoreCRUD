#!/usr/bin/env bash
set -euo pipefail
STORE_DIR="./store"
TMP_DIR="${STORE_DIR}/.tmp"
mkdir -p "$STORE_DIR" "$TMP_DIR"

gen_id() {
  printf '%s-%04d' "$(date +%Y%m%d%H%M%S)" "$((RANDOM%10000))"
}
usage() {
  cat <<EOF
Usage:
  $0 create --name "Name" --email "email"
  $0 read <id>
  $0 update <id> [--name "Name"] [--email "email"]
  $0 delete <id>
  $0 list
  $0 help
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"; shift
atomic_write() {
  local out="$1"; shift
  local tmp
  tmp="$(mktemp "${TMP_DIR}/tmp.XXXXXX")"
  printf "%s\n" "$@" > "$tmp"
  mv "$tmp" "$out"
}

cmd_create() {
  local name="" email=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --email) email="$2"; shift 2 ;;
      *) echo "Unknown flag: $1"; exit 2 ;;
    esac
  done

  if [[ -z "$name" || -z "$email" ]]; then
    echo "ERROR: --name and --email are required" >&2
    exit 2
  fi

  local id
  id="$(gen_id)"
  local file="${STORE_DIR}/user_${id}.txt"

  atomic_write "$file" \
    "id:${id}" \
    "name:${name}" \
    "email:${email}" \
    "created_at:$(date '+%Y-%m-%d %H:%M:%S')"

  echo "Created user: $id"
}
show_user() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: user not found: $file" >&2
    return 1
  fi
  sed -n 's/^/  /p' "$file"
}

cmd_read() {
  local id="$1"
  local file="${STORE_DIR}/user_${id}.txt"
  show_user "$file"
}

cmd_list() {
  shopt -s nullglob 2>/dev/null || true
  local files=("${STORE_DIR}"/user_*.txt)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "(no users)"
    return
  fi
  for f in "${files[@]}"; do
    local id
    id="$(basename "$f" | sed -E 's/^user_(.*)\.txt$/\1/')"
    local name
    name="$(grep '^name:' "$f" 2>/dev/null | cut -d: -f2- || echo '(no name)')"
    printf "%s\t%s\n" "$id" "${name}"
  done
}

cmd_update() {
  if [[ $# -lt 1 ]]; then echo "update needs id"; exit 2; fi
  local id="$1"; shift
  local file="${STORE_DIR}/user_${id}.txt"
  if [[ ! -f "$file" ]]; then echo "ERROR: user $id not found"; exit 1; fi

  declare -A updates
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) updates[name]="$2"; shift 2 ;;
      --email) updates[email]="$2"; shift 2 ;;
      *) echo "Unknown flag: $1"; exit 2 ;;
    esac
  done

  local tmp="$(mktemp "${TMP_DIR}/edit.XXXXXX")"
  cp "$file" "$tmp"

  for k in "${!updates[@]}"; do
    if grep -q "^${k}:" "$tmp"; then
      sed -i.bak "s|^${k}:.*|${k}:${updates[$k]}|" "$tmp" && rm -f "${tmp}.bak"
    else
      printf "%s:%s\n" "$k" "${updates[$k]}" >> "$tmp"
    fi
  done

  printf "updated_at:%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$tmp"
  mv "$tmp" "$file"

  echo "Updated $id"
}
cmd_delete() {
  if [[ $# -ne 1 ]]; then echo "delete needs id"; exit 2; fi
  local id="$1"
  local file="${STORE_DIR}/user_${id}.txt"
  if [[ ! -f "$file" ]]; then echo "ERROR: user $id not found"; exit 1; fi
  rm -f "$file"
  echo "Deleted $id"
}

case "$cmd" in
  help|-h|--help) usage; exit 0 ;;
  create) cmd_create "$@" ;;
  list) cmd_list ;;
  update) cmd_update "$@" ;;
  delete) cmd_delete "$@" ;;
  read) if [[ $# -ne 1 ]]; then echo "read needs id"; exit 2; fi; cmd_read "$1" ;;

  *) echo "Unknown command: $cmd"; usage; exit 2 ;;
esac

