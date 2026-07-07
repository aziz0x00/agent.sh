MODELS=(lfm2.5-thinking)

ENDPOINT_URL='http://localhost:11434/api/chat'
PARAM_TOOL_CHECK='.message.tool_calls != null'
PARAM_TOOL_IDX='.message.tool_calls[0].index'
PARAM_TOOL_CALL='{id: .message.tool_calls[0].function.name, function: {name: .message.tool_calls[0].function.name, arguments: ""}}'
PARAM_ARG_APPEND='.function.arguments += .message.tool_calls[0].function.arguments'
PARAM_TEXT='.message.content // ""'
PARAM_REASONING='.message.thinking // ""'

echo -ne '{
  "model": "'$model'",
  "messages": [], "tools": [],
  "stream": true
}' >$STATE_FILE

function switch_model {
    model=$1
    jq_inplace '.model = "'"$model"'"'
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
    [[ ! -z "$prompt" ]] &&
        __append_message "user" "$(jq -n --arg c "$prompt" '{content: $c}')"

    while true; do
        local response=""
        local tools=()
        curl -f -N -s "$ENDPOINT_URL" \
            --json @$STATE_FILE 2>/dev/null | while IFS= read -r line; do
            [ -z "$line" ] && continue

            [[ "$line" == '[DONE]' ]] && break

            chunk=$line

            if [[ $(jq "$PARAM_TOOL_CHECK" <<<"$chunk") == true ]]; then
                idx=$(jq "$PARAM_TOOL_IDX" <<<"$chunk")
                if [[ -z "${tools[idx]}" ]]; then
                    echo >>$LOGS_FILE
                    tools[idx]=$(jq -r "$PARAM_TOOL_CALL" <<<"$chunk")
                else
                    tools[idx]=$(jq -r "$PARAM_ARG_APPEND" <<<"${tools[idx]}")
                    echo -ne "\x0d ∑ ${#tools[idx]}" >>$LOGS_FILE
                fi
            else
                [[ "$(jq "${PARAM_REASONING}" <<<"$chunk")" != '""' ]] && {
                    jq "${PARAM_REASONING}" -r -j <<<"$chunk" >>$LOGS_FILE
                    continue
                }

                [[ $(jq "$PARAM_TEXT" <<<"$chunk") != '""' ]] && {
                    jq "$PARAM_TEXT" -r -j <<<"$chunk" >&4
                    response="$response$(jq "$PARAM_TEXT" -r -j <<<"$chunk")"
                }
            fi
        done

        [[ ! -z "$response" ]] &&
            __append_message "assistant" "$(jq -n --arg c "$response" '{content: $c}')"

        [[ ${#tools[@]} -eq 0 ]] && return

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
