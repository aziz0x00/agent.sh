TOOL_DEF='{
  "name": "WebFetch",
  "description": "Fetch a URL and convert HTML to readable text using curl piped to html2text. Use for retrieving web page content.",
  "parameters": {
    "type": "object",
    "properties": {
      "url": {
        "type": "string",
        "description": "The URL to fetch."
      }
    },
    "required": ["url"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreWebFetch {
  local parameters="$1"

  local url=$(jq -r '.url' <<<"$parameters")
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "Invalid URL: must start with http:// or https://" >&2
    return 1
  fi

  jq '{
    fmt: (.url|tojson),
    preview: .url,
    nextArgs: [.url]
  }' <<<"$parameters"
}

function WebFetch {
  local url=$1

  local html
  if ! html=$(curl -sSL --max-time 30 -A 'Mozilla/5.0' "$url" 2>&1); then
    echo "Error: $html"
  else
    local output=$(html2text 2>&1 <<<"$html")
    echo "${output:-Error: No content received from $url}"
  fi
}