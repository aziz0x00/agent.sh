TOOL_DEF='{
  "name": "Grep",
  "description": "Search for patterns in file contents using ripgrep.",
  "parameters": {
    "type": "object",
    "properties": {
      "pattern": {
        "type": "string",
        "description": "The regex pattern to search for in file contents"
      },
      "path": {
        "type": "string",
        "description": "The directory to search in. Defaults to the current working directory."
      },
      "include": {
        "type": "string",
        "description": "File pattern to include in the search (e.g. \"*.js\", \"*.{ts,tsx}\")"
      }
    },
    "required": ["pattern"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreGrep {
  local path=$(jq -r '.path // "."' <<<"$1")
  local include=$(jq -r '.include // ""' <<<"$1")
  local parameters=$(jq '.path = (.path // ".") | .include = (.include // "")' <<<"$1")

  jq '{
    fmt: (.pattern|tojson) + " @" + .path + " +" + (.include|tojson),
    preview: .,
    nextArgs: [.pattern, .path, .include]
  }' <<<"$parameters"
}

function Grep {
  local pattern=$1
  local path=$2
  local include=$3

  local args=("-nH" "--field-match-separator=|" "--multiline" "--regexp" "$pattern")
  if [[ -n "$include" ]]; then
    args+=("--glob" "$include")
  fi
  args+=("$path")

  rg "${args[@]}" 2>&1
  local exit_code=$?

  if [[ $exit_code -ne 0 ]] && [[ $exit_code -ne 1 ]]; then
    echo "Error: Grep failed with exit code $exit_code"
  fi
}
