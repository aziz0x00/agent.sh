TOOL_DEF='{
  "name": "WebSearch",
  "description": "Search the web using Exa AI. Returns relevant search results with content snippets.",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "The search query to execute."
      }
    },
    "required": ["query"]
  }
}'

# @return json: {fmt: string, preview: string, nextArgs: [string]}
function PreWebSearch {
  local parameters="$1"

  jq '{
    fmt: (.query|tojson),
    preview: .query,
    nextArgs: [.query]
  }' <<<"$parameters"
}

function WebSearch {
  local query=$1

  local body=$(jq -n --arg query "$query" '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "web_search_exa",
      "arguments": {
        "query": $query,
        "type": "auto",
        "numResults": 8,
        "livecrawl": "fallback",
        "contextMaxCharacters": 10000
      }
    }
  }')

  local response=$(
    curl -s "https://mcp.exa.ai/mcp" --json @<(echo "$body") \
      -H 'Accept: application/json, text/event-stream'
  )

  # Parse SSE response: extract data lines and combine JSON
  local result=$(echo "$response" | grep "^data:" |
    sed 's/^data: //' | jq -s '.[0].result.content[0].text // empty')

  if [[ -z "$result" ]]; then
    echo "Error: No results found or invalid response from search API"
    echo "$response"
  else
    echo "$result"
  fi
}
