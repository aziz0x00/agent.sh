TOOL_DEF='{
  "name": "Write",
  "description": "Write data to a file on the local filesystem, optionally creating or overwriting it.",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Absolute or relative path to the target file."
      },
      "content": {
        "type": "string",
        "description": "Text content to write to the file."
      },
      "mode": {
        "type": "string",
        "enum": ["w", "a"],
        "default": "w",
        "description": "`w` to overwrite, `a` to append."
      }
    },
    "required": ["path", "content"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreWrite {
  local parameters=$(jq '.mode = (.mode // "w")' <<<"$1") # default to "w"

  local path=$(jq -r .path <<<"$parameters")
  local content=$(jq -r .content <<<"$parameters")

  [[ -w "$path" ]] || [[ -w "$(dirname "$path")" ]] || {
    echo "Error: File '$path' does not writable"
    return 1
  }

  local preview=$(diff --color=always <(cat "$path" 2>/dev/null) <(echo "$content") 2>&1)

  jq --rawfile preview <(echo "$path"; cat <<<"$preview") '{
    fmt: .path,
    preview: $preview,
    nextArgs: [.path, .content, .mode]
  }' <<<"$parameters"
}

function Write {
  local path=$1
  local content=$2
  local mode=$3

  if [[ "$mode" == "a" ]]; then
    echo -n "$content" >>"$path"
  else
    echo -n "$content" >"$path"
  fi

  [[ $? -eq 0 ]] && echo "Write succeded." || echo "Unexpected error."
}
