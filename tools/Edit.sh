TOOL_DEF='{
  "name": "Edit",
  "description": "Edit an existing file by replacing content at a specific line range.",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Absolute or relative path to the file to edit."
      },
      "oldString": {
        "type": "string",
        "description": "The text to replace"
      },
      "newString": {
        "type": "string",
        "description": "The text to replace it with (must be different from oldString)"
      },
      "replaceAll": {
        "type": "boolean",
        "default": false,
        "description": "Replace all occurrences of oldString"
      }
    },
    "required": ["path", "oldString", "newString"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreEdit {
  local parameters=$(jq '.replaceAll = (.replaceAll // false)' <<<"$1") # set defaults

  local path=$(jq -r .path <<<"$parameters")

  [[ -w "$path" ]] || {
    echo "Error: File '$path' does not exist or not readable."
    return 1
  }

  local oldString=$(jq -r .oldString <<<"$parameters")
  local newString=$(jq -r .newString <<<"$parameters")
  local replaceAll=$(jq -r .replaceAll <<<"$parameters")

  [[ "$oldString" == "$newString" ]] &&
    echo "oldString and newString must be different" && return 1

  local tmp=$(mktemp)
  local PYCODE='
import json, sys
data = json.load(sys.stdin)
with open(data["path"]) as f:
    src = f.read()
data["old"] not in src and exit(1)
with open(data["tmp"], "w") as f:
    f.write(src.replace(data["old"], data["new"], -2 * data["all"] + 1))
'
  local PYINPUT='{path: $p, old: $o, new: $n, all: $a, tmp: $t}'
  jq -n --arg p "$path" --arg o "$oldString" --arg n "$newString" \
    --argjson a "$replaceAll" --arg t "$tmp" "$PYINPUT" | python3 -c "$PYCODE" 2>&1
  [[ "${PIPESTATUS[1]}" -ne 0 ]] && echo "oldString not in file" && return 1

  local preview=$(diff "$path" "$tmp" --color=always 2>&1)

  jq --rawfile preview <(echo $path; cat <<<$preview) --arg tmp $tmp '{
    fmt: .path,
    preview: $preview,
    nextArgs: [.path, $tmp]
  }' <<<"$parameters"
}

function Edit {
  local path=$1
  local tmp=$2

  cat "$tmp" >"$path"
  [[ $? -eq 0 ]] && echo "Edit succeded." || echo "Unexpected error."
  rm "$tmp" &>/dev/null
}
