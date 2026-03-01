TOOL_DEF='{
  "name": "Bash",
  "description": "Execute a Bash command shell environment.\n - When using curl and you expect html output, prefer to use `html2text`.\n - You also have `pdftotext` available for reading pdfs.\n - Always use `uv run --with <package-name>` for python code when a package is needed instead of checking if the package exists",
  "parameters": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "The Bash command line to execute. May include pipes, redirects, etc."
      },
      "timeout": {
        "type": "integer",
        "default": 30,
        "description": "Maximum execution time in seconds. Optional; default is 30."
      }
    },
    "required": ["command"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreBash {
  local parameters=$(jq '.timeout = (.timeout // 30)' <<<"$1") # set defaults

  local lang=bash

  case "$(jq -r '.command' <<<"$parameters" | head -1)" in
  *uv* | *python*) lang=python ;;
  esac

  local preview=$(jq -r '.command' <<<"$parameters" | (bat --language $lang --color always || cat))

  jq --rawfile preview <(cat <<<"$preview") '{
    fmt: (.command|tojson),
    preview: $preview,
    nextArgs: [.command, .timeout]
  }' <<<"$parameters"
}

function Bash {
  local command=$1
  local timeout=$2

  local output=$(timeout "$timeout" bash -c "$command" 2>&1 <&-)
  local exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    echo "Error: Command timed out after $timeout seconds. Output: $output"
  elif [[ $exit_code -ne 0 ]]; then
    echo "Error: Command exited with code $exit_code. Output: $output"
  else
    echo "$output"
  fi
}
