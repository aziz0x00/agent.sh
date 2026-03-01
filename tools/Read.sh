TOOL_DEF='{
  "name": "Read",
  "description": "Read the contents of a file from the local filesystem.",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Absolute or relative path to the file to read."
      },
      "offset": {
        "type": "integer",
        "minimum": 0,
        "description": "The line number to start reading from (0-based)"
      },
      "limit": {
        "type": "integer",
        "default": 2000,
        "description": "The number of lines to read"
      }
    },
    "required": ["path"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreRead {
  local parameters=$(jq '
  .offset = (.offset // 0) |
  .limit = (.limit // 2000)
  ' <<<"$1") # set defaults

  local path=$(jq -r .path <<<"$parameters")
  if [[ ! -r "$path" ]]; then
    echo "Error: File '$path' does not exist or not readable."
    return 1
  fi
  local limit=$(jq -r .limit <<<"$parameters")
  local offset=$(jq -r .offset <<<"$parameters")
  local preview=$(tail -n +"$((offset + 1))" "$path" | head -n "$limit" 2>&1)

  jq --rawfile preview <(cat <<<"$preview") '{
    fmt: .path,
    preview: .,
    nextArgs: [$preview]
  }' <<<"$parameters"
}

function Read {
  local output=$1
  cat <<<"$output"
}
