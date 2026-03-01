TOOL_DEF='{
  "name": "Question",
  "description": "Use this tool when you need to ask the user questions during execution. ALWAYS use this when asking questions. This allows you to:\n1. Gather user preferences or requirements\n2. Clarify ambiguous instructions\n3. Get decisions on implementation choices as you work\n4. Offer choices to the user about what direction to take.\n\nUsage notes:\n- a \"Type your own answer\" option is added automatically; dont include \"Other\" or catch-all options\n- Answers are returned as arrays of labels; set `multiple: true` to allow selecting more than one\n- If you recommend a specific option, make that the first option in the list and add \"(Recommended)\" at the end of the label",
  "parameters": {
    "type": "object",
    "properties": {
      "questions": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "header": {"type": "string"},
            "options": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "label": {"type": "string"},
                  "description": {"type": "string"}
                }
              }
            },
            "multiple": {"type": "boolean"}
          },
          "required": ["header", "options"]
        }
      }
    },
    "required": ["questions"]
  }
}'

_CUSTOM_OPTION="[Type your own answer]"
_LABEL_DELIMITER="|>-<|"
_OPTION_DELIMITER="|>~<|"

function PreQuestion {
  local parameters=$1
  local count=$(jq -r '.questions | length // 0' <<<"$parameters")
  local fmt="Asking $count question(s)"

  jq --arg fmt "$fmt" '{
    fmt: $fmt,
    preview: .,
    nextArgs: [.questions]
  }' <<<"$parameters"
}

function _ask {
  local questions=$1
  local answers="{}"

  while read -r question; do
    [[ -z "$question" ]] && continue

    local header=$(jq -r '.header' <<<"$question")
    local multiple=$(jq -r '.multiple // false' <<<"$question")

    local gum_args=("choose"
      "--header" "$header"
      "--padding" "1 2"
      "--unselected-prefix" "[ ] "
      "--selected-prefix" "[✔] "
      "--cursor-prefix" "[ ] "
      "--label-delimiter" "$_LABEL_DELIMITER"
      "--output-delimiter" "$_OPTION_DELIMITER"
      "--input-delimiter" "$_OPTION_DELIMITER")

    [[ "$multiple" == "true" ]] && gum_args+=("--no-limit")

    local options=$(jq -r \
      --arg ld "$_LABEL_DELIMITER" --arg od "$_OPTION_DELIMITER" --arg custom "$_CUSTOM_OPTION" \
      '[.options[] | .label + ": " + .description + $ld + .label] | . + [$custom + $ld + $custom] | join($od)' <<<"$question")

    local selected=$(echo "$options" | gum "${gum_args[@]}") || continue

    local answer="[]"

    if [[ "$multiple" == "true" ]]; then
      while IFS= read -r lab; do
        lab=$(jq -r "." <<<"$lab")
        [[ -z "$lab" ]] && continue
        if [[ "$lab" == "$_CUSTOM_OPTION" ]]; then
          lab=$(gum input --header "$header" --padding "1 2" </dev/tty) || continue
        fi
        answer=$(jq --arg a "$lab" '. + [$a]' <<<"$answer")
      done < <(jq -R --arg od "$_OPTION_DELIMITER" 'split($od) | .[]' <<<"$selected")
    else
      if [[ "$selected" == "$_CUSTOM_OPTION" ]]; then
        local custom_ans
        custom_ans=$(gum input --header "$header" --padding "1 2" </dev/tty) || continue
        answer=$(jq -n --arg ans "$custom_ans" '[$ans]')
      else
        [[ -n "$selected" ]] && answer=$(jq -n --arg a "$selected" '[$a]')
      fi
    fi

    answers=$(jq --argjson ans "$answer" --arg h "$header" '.[$h] = $ans' <<<"$answers")
  done < <(jq -c '.[]' <<<"$questions")

  echo "$answers"
}

function Question {
  local questions="$1"
  local answers=

  while true; do
    answers=$(_ask "$questions")
    local table=$(jq 'to_entries[] | [.key, (.value | join("; "))] | @csv' -r <<<"$answers" |
      gum table --columns "Question, Answers" -p | sed 's/\x1b\[[^m]*m//g') # gum table is bad
    gum style --padding "1 0 0 2" "$table" --foreground "#a8aab0" >/dev/tty
    gum confirm --padding "1 2" "Confirm answers?" || continue
    break
  done

  jq '[.[]]' <<<"$answers" # only values
}
