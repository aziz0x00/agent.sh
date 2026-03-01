TOOL_DEF='{
  "name": "Glob",
  "description": "Return a list of files matching a glob pattern.",
  "parameters": {
    "type": "object",
    "properties": {
      "pattern": {
        "type": "string",
        "description": "Glob pattern to match files against."
      },
      "root_dir": {
        "type": "string",
        "description": "Base directory from which the pattern is evaluated. Defaults to the current working directory."
      },
      "case_sensitive": {
        "type": "boolean",
        "default": true,
        "description": "Whether the matching should be case‑sensitive."
      }
    },
    "required": ["pattern"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreGlob {
  local parameters=$(jq '
  .case_sensitive = (.case_sensitive // true) |
  .root_dir = (.root_dir // ".")
  ' <<<"$1") # set defaults

  local pattern=$(jq -r .pattern <<<"$parameters")
  local root_dir=$(jq -r .root_dir <<<"$parameters")

  shopt -s globstar nullglob
  if [[ "$(jq -r .case_sensitive <<<"$parameters")" == false ]]; then
    shopt -s nocaseglob
  fi
  pushd "$root_dir" &>/dev/null || {
    echo "Can't access directory '$root_dir'"
    return 1
  }
  local matches=()
  for file in $pattern; do
    matches+=("$(realpath "$file")")
  done
  popd >/dev/null

  local preview=$(printf '%s\n' "${matches[@]}")

  jq --rawfile preview <(cat <<<"$preview") '{
    fmt: .root_dir + "/" + .pattern,
    preview: $preview,
    nextArgs: [$preview]
  }' <<<"$parameters"
}

function Glob {
  local preview=$1
  echo -n "$preview"
}
