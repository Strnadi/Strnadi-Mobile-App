#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/concat_changelog_range.sh --lang <en|cs> --from <x.y.z> --to <x.y.z>

Example:
  scripts/concat_changelog_range.sh --lang en --from 1.4.15 --to 1.4.18
EOF
}

normalize_version() {
  local major minor patch
  IFS='.' read -r major minor patch <<<"$1"
  printf '%03d%03d%03d' "$((10#$major))" "$((10#$minor))" "$((10#$patch))"
}

in_range_inclusive() {
  local version="$1"
  local from="$2"
  local to="$3"
  local nv nfrom nto
  nv="$(normalize_version "$version")"
  nfrom="$(normalize_version "$from")"
  nto="$(normalize_version "$to")"
  [[ "$nv" > "$nfrom" || "$nv" == "$nfrom" ]] && [[ "$nv" < "$nto" || "$nv" == "$nto" ]]
}

lang=""
from=""
to=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang|-l)
      lang="${2:-}"
      shift 2
      ;;
    --from|-f)
      from="${2:-}"
      shift 2
      ;;
    --to|-t)
      to="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$lang" || -z "$from" || -z "$to" ]]; then
  usage >&2
  exit 1
fi

if [[ ! "$lang" =~ ^(en|cs)$ ]]; then
  echo "Unsupported language '$lang'. Use 'en' or 'cs'." >&2
  exit 1
fi

if [[ ! "$from" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$to" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versions must match x.y.z format." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lang_dir="$repo_root/changelogs/$lang"

if [[ ! -d "$lang_dir" ]]; then
  echo "Missing changelog directory: $lang_dir" >&2
  exit 1
fi

if [[ "$(normalize_version "$from")" > "$(normalize_version "$to")" ]]; then
  echo "--from must be lower or equal to --to." >&2
  exit 1
fi

if [[ ! -f "$lang_dir/$from.md" ]]; then
  echo "Missing version file: $lang_dir/$from.md" >&2
  exit 1
fi

if [[ ! -f "$lang_dir/$to.md" ]]; then
  echo "Missing version file: $lang_dir/$to.md" >&2
  exit 1
fi

unsorted_versions=()
while IFS= read -r file; do
  version="$(basename "$file" .md)"
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    unsorted_versions+=("$version")
  fi
done < <(find "$lang_dir" -maxdepth 1 -type f -name '*.md' -print)

if [[ ${#unsorted_versions[@]} -eq 0 ]]; then
  echo "No versioned changelog files found in $lang_dir." >&2
  exit 1
fi

versions=()
while IFS= read -r version; do
  versions+=("$version")
done < <(
  for version in "${unsorted_versions[@]}"; do
    printf '%s %s\n' "$(normalize_version "$version")" "$version"
  done | sort | awk '{print $2}'
)

label="Version"
if [[ "$lang" == "cs" ]]; then
  label="Verze"
fi

printed=0
for version in "${versions[@]}"; do
  if in_range_inclusive "$version" "$from" "$to"; then
    if [[ "$printed" -gt 0 ]]; then
      printf '\n'
    fi
    printf '%s %s\n' "$label" "$version"
    cat "$lang_dir/$version.md"
    printed=$((printed + 1))
  fi
done

if [[ "$printed" -eq 0 ]]; then
  echo "No versions found in range $from to $to." >&2
  exit 1
fi
