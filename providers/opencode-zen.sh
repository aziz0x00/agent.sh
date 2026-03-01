MODELS=(minimax-m2.5-free glm-5 kimi-k2.5 big-pickle grok-code claude-sonnet-4-5)

SDK="" # ENUM: "openai_compat" | "anthropic"

declare -A \
    ENDPOINT_URL=(
        [anthropic]='https://opencode.ai/zen/v1/messages'
        [openai_compat]='https://opencode.ai/zen/v1/chat/completions') \
    PARAM_TOTAL_TOKENS=(
        [anthropic]='.usage.input_tokens + .usage.output_tokens' [openai_compat]='.usage.total_tokens') \
    PARAM_TOOL_CHECK=(
        [anthropic]='.content_block.type == "tool_use" or .delta.partial_json != null'
        [openai_compat]='(.choices[0].delta.tool_calls|length) != 0') \
    PARAM_TOOL_IDX=([anthropic]='.index' [openai_compat]='.choices[0].delta.tool_calls[0].index') \
    PARAM_TOOL_CALL=(
        [anthropic]='{id: .content_block.id, function: {name: .content_block.name, arguments: ""}}'
        [openai_compat]='.choices[0].delta.tool_calls[0]') \
    PARAM_ARG_APPEND=(
        [anthropic]='.function.arguments += $chunk.delta.partial_json'
        [openai_compat]='.function.arguments += $chunk.choices[0].delta.tool_calls[0].function.arguments') \
    PARAM_REASONING=(
        [anthropic]='.delta.thinking // ""'
        [openai_compat]='.choices[0].delta.reasoning_content // .choices[0].delta.reasoning // ""') \
    PARAM_TEXT=([anthropic]='.delta.text // ""' [openai_compat]='.choices[0].delta.content // ""') \
    KEY_HEADER=([anthropic]='x-api-key:' [openai_compat]='Authorization: Bearer')

echo -ne '{
  "temperature": 1.0, "top_p": 0.95,
  "messages": [], "tools": [],
  "stream": true
}' >$STATE_FILE

function __transform_state_openai_compat { cp "$STATE_FILE" "$TMP_BASE.sdk.json"; }
function __transform_state_anthropic {
    transformed=$TMP_BASE.sdk.json
    cp $STATE_FILE $transformed

    jq '
    # tools schema
    .tools |= map(.function | .input_schema = .parameters | del(.parameters))

    # messages format
    | .messages |= map(
      if (.content|type) == "string" and .role != "tool" then
        .content = [{ type: "text", text: .content }]
      else . end)

    # system prompt
    | .system = [.messages[] | select(.role == "system") | .content[0]]
    | .messages |= map(select(.role != "system"))

    # tool calls
    | .messages |= map(
      if .role == "assistant" and .tool_calls != null then
        .content += (
          .tool_calls
          | map({
              type: "tool_use",
              id: .id,
              name: .function.name,
              input: (.function.arguments|fromjson)
            })
        ) | del(.tool_calls)
      else . end)

    # tool results
    | .messages |= map(
      if .role == "tool" then
        {
          role: "user",
          content: [{
            type: "tool_result",
            tool_use_id: .tool_call_id,
            content: .content
          }]
        }
      else . end)' <"$transformed" >$transformed.tmp && mv "$transformed.tmp" "$transformed"
}

function switch_model {
    model=$1
    jq_inplace '.model = "'"$model"'"'

    case "$model" in
    minimax-m2.1* | claude-*) SDK="anthropic" ;;
    glm-* | minimax-m2.5* | kimi-k2* | grok-code | big-pickle) SDK="openai_compat" ;;
    esac
}

function activate_tools {
    declare -n tools=$1
    for tool in "${tools[@]}"; do
        jq_inplace --argjson tool "$tool" \
            '.tools += [{"type": "function", "function": $tool}]'
    done
}

function __append_message {
    local role=$1
    local rest=$2
    jq_inplace --arg role "$role" --slurpfile rest <(cat <<<"$rest") \
        '.messages += [{"role": $role} + $rest[0]]'
}

function add_system_prompt {
    local content=$1
    __append_message "system" "$(jq -n --arg c "$content" '{content: $c}')"
}

function set_attachments { echo "Binary attachments are not supported by the provider."; }

function api_completion {
    local prompt=$1

    [[ ! -z "$prompt" ]] && # this can be empty during tool calls
        __append_message "user" "$(jq -n --arg c "$prompt" '{content: $c}')"

    while true; do
        local response=""
        local tools=()
        __transform_state_$SDK
        local state=$TMP_BASE'.sdk.json'

        local tool_name

            # -H 'x-opencode-session: :)' \
        curl -f -N -s "${ENDPOINT_URL[$SDK]}" \
            $([[ -z "$OPENCODE_ZEN_API_KEY" ]] || echo -H "${KEY_HEADER[$SDK]} ${OPENCODE_ZEN_API_KEY}") \
            --json @$state 2>>$LOGS_FILE | while IFS= read -r line; do
            # echo "$line" >>$LOGS_FILE
            [ -z "$line" ] && continue

            grep -Eq '^data: ' <<<"$line" || continue

            chunk=$(echo "$line" | sed -e 's/^data: //')
            [[ "$chunk" == '[DONE]' ]] && break

            [[ $(jq .usage <<<"$chunk") != null ]] &&
                total_tokens=$(jq -r "${PARAM_TOTAL_TOKENS[$SDK]}" <<<"$chunk" | numfmt --to=si)

            if [[ $(jq "${PARAM_TOOL_CHECK[$SDK]}" <<<"$chunk") == true ]]; then
                idx=$(jq "${PARAM_TOOL_IDX[$SDK]}" <<<"$chunk")
                if [[ -z "${tools[idx]}" ]]; then
                    tools[idx]=$(jq -r "${PARAM_TOOL_CALL[$SDK]}" <<<"$chunk")
                    echo >>$LOGS_FILE
                    tool_name=$(jq -r -j '.function.name' <<<"${tools[$idx]}")
                else
                    tools[idx]=$(jq -r --argjson chunk "$chunk" "${PARAM_ARG_APPEND[$SDK]}" <<<"${tools[idx]}")
                    echo -ne '\x0d '"$tool_name ∑ ${#tools[idx]}" >>$LOGS_FILE
                fi
            else
                [[ "$(jq "${PARAM_REASONING[$SDK]}" <<<"$chunk")" != '""' ]] && {
                    jq "${PARAM_REASONING[$SDK]}" -r -j <<<"$chunk" >>$LOGS_FILE
                }

                [[ $(jq "${PARAM_TEXT[$SDK]}" <<<"$chunk") != '""' ]] && {
                    jq "${PARAM_TEXT[$SDK]}" -r -j <<<"$chunk" >&4
                    response="$response$(jq "${PARAM_TEXT[$SDK]}" -r -j <<<"$chunk")"
                }
            fi
        done
        [[ -z "$response" ]] && [[ "${#tools[@]}" -eq 0 ]] &&
            echo "[No response, retrying in 2s..]" >>$LOGS_FILE && sleep 2 && continue

        [[ -n "$response" ]] &&
            __append_message "assistant" "$(jq -n --arg c "$response" '{content: $c}')"

        [[ -z "${tools[@]}" ]] && return

        local rest='{"tool_calls": []}'
        for tool in "${tools[@]}"; do
            [[ -z "$tool" ]] && continue
            rest=$(jq --argjson t "$tool" '.tool_calls += [$t]' <<<"$rest")
        done
        __append_message "assistant" "$rest"

        for tool in "${tools[@]}"; do
            [[ -z "$tool" ]] && continue
            toolname=$(jq -r ".function.name" <<<"$tool")
            parameters=$(jq -r ".function.arguments" <<<"$tool")
            resp=
            tool_call "$toolname" "$parameters" "resp"
            rest=$(jq --rawfile resp <(cat <<<"$resp") \
                '{tool_call_id: .id, name: .function.name, content: $resp}' <<<"$tool")
            __append_message "tool" "$rest"
        done
    done
}
