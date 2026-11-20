#!/usr/bin/env bash
# safe_file_deleter.sh - move files into a trash directory with metadata so they
# can be restored, instead of removing them permanently.
#
# All state lives under a single trash root. Each trashed file gets a unique
# entry directory containing the payload plus a small metadata file. We keep the
# original absolute path in the metadata so restore can put the file back even
# after the caller has changed directories.

set -euo pipefail

# Default trash root. Callers may override before sourcing, or pass an explicit
# root to each function. We default to a path under the user's home so the
# library is usable without configuration.
: "${SFD_TRASH_ROOT:=${HOME:-/tmp}/.local/share/safe-file-deleter}"

# sfd_usage prints a short description of the exported functions.
sfd_usage() {
  cat <<'EOF'
usage: safe_file_deleter.sh provides:
  sfd_trash <path> [trash_root]   move a file into the trash
  sfd_restore <entry> [trash_root] move a trashed file back
  sfd_list [trash_root]           list trashed entries
EOF
}

# sfd_abspath resolves a path to an absolute one without requiring the file to
# exist. We avoid realpath -e because trashed payloads may already be gone.
sfd_abspath() {
  local target=$1
  if [[ $target == /* ]]; then
    printf '%s\n' "$target"
  else
    printf '%s/%s\n' "$PWD" "$target"
  fi
}

# sfd_entry_dir returns the directory that holds a single trash entry.
sfd_entry_dir() {
  local root=$1 entry=$2
  printf '%s/%s\n' "$root" "$entry"
}

# sfd_metadata_path returns the metadata file for an entry.
sfd_metadata_path() {
  local root=$1 entry=$2
  printf '%s/meta\n' "$(sfd_entry_dir "$root" "$entry")"
}

# sfd_payload_path returns the payload file for an entry.
sfd_payload_path() {
  local root=$1 entry=$2
  printf '%s/payload\n' "$(sfd_entry_dir "$root" "$entry")"
}

# sfd_new_entry_name builds a collision-free entry name. We combine the basename
# with the current epoch seconds and a counter so two files with the same name
# trashed in the same second still get distinct entries.
sfd_new_entry_name() {
  local root=$1 base=$2
  local stamp counter candidate
  stamp=$(date +%s)
  counter=0
  while :; do
    if (( counter == 0 )); then
      candidate="${base}.${stamp}"
    else
      candidate="${base}.${stamp}.${counter}"
    fi
    if [[ ! -e "$root/$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    counter=$((counter + 1))
  done
}

# sfd_trash moves a regular file into the trash directory. It refuses to trash
# directories and refuses to trash a path that does not exist, because silently
# succeeding on a missing file would hide caller bugs.
sfd_trash() {
  local path=${1:?sfd_trash: path required}
  local root=${2:-$SFD_TRASH_ROOT}
  local abs base entry payload meta

  if [[ ! -e "$path" ]]; then
    printf 'sfd_trash: no such file: %s\n' "$path" >&2
    return 1
  fi
  if [[ -d "$path" ]]; then
    printf 'sfd_trash: refusing to trash a directory: %s\n' "$path" >&2
    return 1
  fi

  abs=$(sfd_abspath "$path")
  base=$(basename -- "$abs")

  mkdir -p -- "$root"
  entry=$(sfd_new_entry_name "$root" "$base")
  mkdir -p -- "$(sfd_entry_dir "$root" "$entry")"

  payload=$(sfd_payload_path "$root" "$entry")
  meta=$(sfd_metadata_path "$root" "$entry")

  mv -- "$abs" "$payload"
  {
    printf 'original=%s\n' "$abs"
    printf 'name=%s\n' "$base"
  } > "$meta"

  printf '%s\n' "$entry"
}

# sfd_restore moves a trashed payload back to its original location. It creates
# the parent directory if needed, but refuses to overwrite an existing file so a
# restore cannot clobber newer data.
sfd_restore() {
  local entry=${1:?sfd_restore: entry required}
  local root=${2:-$SFD_TRASH_ROOT}
  local payload meta original parent

  payload=$(sfd_payload_path "$root" "$entry")
  meta=$(sfd_metadata_path "$root" "$entry")

  if [[ ! -f "$meta" ]]; then
    printf 'sfd_restore: no such entry: %s\n' "$entry" >&2
    return 1
  fi
  if [[ ! -f "$payload" ]]; then
    printf 'sfd_restore: entry payload missing: %s\n' "$entry" >&2
    return 1
  fi

  original=$(sfd_read_meta "$meta" original)
  if [[ -z "$original" ]]; then
    printf 'sfd_restore: entry metadata has no original path: %s\n' "$entry" >&2
    return 1
  fi
  if [[ -e "$original" ]]; then
    printf 'sfd_restore: refusing to overwrite existing path: %s\n' "$original" >&2
    return 1
  fi

  parent=$(dirname -- "$original")
  mkdir -p -- "$parent"
  mv -- "$payload" "$original"
  rm -f -- "$meta"
  rmdir -- "$(sfd_entry_dir "$root" "$entry")" 2>/dev/null || true

  printf '%s\n' "$original"
}

# sfd_read_meta reads a single key from a metadata file. We parse with a plain
# read loop rather than sourcing the file so a hostile payload cannot execute
# shell code during restore.
sfd_read_meta() {
  local meta=$1 key=$2 line
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$key="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done < "$meta"
  return 1
}

# sfd_list prints each trashed entry name, one per line. Entries without a meta
# file are skipped because they cannot be restored.
sfd_list() {
  local root=${1:-$SFD_TRASH_ROOT}
  local entry
  [[ -d $root ]] || return 0
  for entry in "$root"/*; do
    [[ -e $entry ]] || continue
    [[ -f "$entry/meta" ]] || continue
    printf '%s\n' "$(basename -- "$entry")"
  done
}

# When executed directly rather than sourced, dispatch a small CLI so the script
# is usable on its own. When sourced, only the functions are defined.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  case ${1:-} in
    trash)
      shift
      sfd_trash "$@"
      ;;
    restore)
      shift
      sfd_restore "$@"
      ;;
    list)
      shift
      sfd_list "$@"
      ;;
    *)
      sfd_usage
      exit 1
      ;;
  esac
fi
