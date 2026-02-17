#!/bin/bash

_DIR=$(dirname "${BASH_SOURCE[0]}")

[[ "$1" == "-raw" ]] && RAW_OUTPUT=true && shift
TMP_BASE=$(mktemp -u)
STATE_FILE=$TMP_BASE.json
LOGS_FILE=$TMP_BASE.log
touch "$LOGS_FILE" &&
    [[ ! -z "$TMUX_PANE" ]] &&
    tmux splitw -dv -l 5 'echo -e "\e[38;5;244mLOGS('$LOGS_FILE')"; tail -f '$LOGS_FILE''

set -a; source "$_DIR"/.env; set +a # poppulate env
source "$_DIR"/providers/opencode-zen.sh

function jq_inplace { jq "$@" <$STATE_FILE >${STATE_FILE}.tmp && mv ${STATE_FILE}.tmp $STATE_FILE; }

switch_model ${MODELS[0]}

add_system_prompt "$(cat "$_DIR"/system_prompt.md)"
add_system_prompt "Current date: $(date "+%a %b %d %Y")"

declare -A TOOLS ALLOWED_TOOLS SAFE_TOOLS=([Skill]=1 [WebSearch]=1 [Question]=1) # TODO: do better tool perms mgmt
for tool in Question Read Glob Grep WebSearch Skill Edit Write Bash; do
    source "$_DIR"/tools/${tool}.sh
    TOOLS[$tool]=$TOOL_DEF
done && activate_tools TOOLS

function prompt_user {
    [[ ! -z "$RAW_OUTPUT" ]] && exit
    while true; do
        local width=$(($(tput cols) - 2)) && ((width > 80)) && width=80
        user_prompt=""
        user_prompt=$(gum write --width $width --header="$model" --height=3 </dev/tty)
        [ $? -ne 0 ] && exit # ^D
        [ -z "$user_prompt" ] && continue
        [[ $width -gt ${#user_prompt} ]] && width=0
        gum style --width $width --margin '0 0' --border=normal --padding="0 1" "$user_prompt"

        case "$user_prompt" in
        /state    | /s) ${EDITOR:-vim} $STATE_FILE ;;
        /continue | /c) user_prompt="" && return ;; # useful after manual modification by /s
        /logs     | /l) less $LOGS_FILE ;;
        # /agent    | /a) switch_agent ;;
        /model    | /m) switch_model $(echo "${MODELS[@]}" |
            gum choose --input-delimiter=" ") ;;
        *) return ;;
        esac
    done
}

function tool_call {
    local funcname=$1
    local parameters=$2
    local result_var=$3

    MAX_OUTPUT=30000

    declare -n result=$result_var

    kill -$SIG_STOP $mdcat_pid 2>/dev/null && sleep .1 # sometimes it goes too fast and python is slow

    [[ -z "${TOOLS[$funcname]}" ]] && result="Tool unavailable." && return

    local output
    output=$(Pre$funcname "$parameters")
    [[ $? -ne 0 ]] && result="$output" && return # immediately exit on error

    jq .nextArgs <<<"$output" >>$LOGS_FILE
    printf "$funcname>\n%s\n\e[38;5;244m<$funcname\n" "$(jq -r .preview <<<"$output")" >>$LOGS_FILE

    fmt=$(jq -c -r .fmt <<<"$output")

    fun=$(gum style "  › $funcname" --bold)
    par=$(gum style "$fmt" --foreground '#93a1a1')

    local status_code=0
    [[ -z "${ALLOWED_TOOLS[$fmt]}""${SAFE_TOOLS[$funcname]}" ]] && {
        [[ -f "$NOTIFICATION_SOUND" ]] && { # delayed alert
            (
                sleep 5
                ffplay -nodisp -autoexit -volume 70 "$NOTIFICATION_SOUND" &>/dev/null
            ) &
            sound_pid=$!
        }
        local prompt=$(gum style "$fun $par" \
            --foreground '#e5c07b')$'\n\n Approve invocation?'
        answer=$(echo -e "Yes\nYes, always allow this signature\nNo, adjust approach" |
            gum choose --header="$prompt")

        [[ -n "$sound_pid" ]] && [[ "$sound_pid" == "$(jobs -rp | tail -1)" ]] && kill $sound_pid &>/dev/null

        case "$answer" in
        Yes) ;;
        "Yes, always"*)
            ALLOWED_TOOLS[$fmt]=1
            echo "Tool allowed: " "$fmt" >>$LOGS_FILE
            ;;
        *) status_code=1 ;;
        esac
    }

    gum style "$fun $par" --foreground \
        $([[ "$status_code" -eq 0 ]] && echo '#34d399' || echo '#e5c07b' --faint) >/dev/tty

    if [[ "$status_code" -eq 0 ]]; then
        local nextArgs=()
        jq -c '.nextArgs[]' <<<"$output" | while read -r line; do
            nextArgs+=("$(jq -r '.' <<<"$line")")
        done
        result=$($funcname "${nextArgs[@]}" | tee -a $LOGS_FILE)
        result=$(echo "$result" | head -c $MAX_OUTPUT)
    fi

    kill -$SIG_PLAY $mdcat_pid 2>/dev/null
    return $status_code
}

function __consume_pipe {
    local input=$(mktemp)
    cat - >$input
    if [[ $(file -b --mime-type "$input") =~ image ]]; then
        set_attachments "$input"
    else
        user_prompt=$user_prompt$'\n\n---\n\n'"$(cat $input)"
    fi
    rm $input
}

function clean_exit {
    fuser --silent --kill "$LOGS_FILE"
    rm -f $TMP_BASE*
    kill -9 $mdcat_pid 2>/dev/null
    exit
}
trap "clean_exit" EXIT
trap '[ -z "$user_prompt" ] && clean_exit' INT # to interrupt generation and go back to prompt

user_prompt=$@
[[ -z "$@" ]] && prompt_user
[[ -p /dev/stdin ]] || [[ -f /dev/stdin ]] && __consume_pipe # should be after prompt_user

# setup mdcat process for pretty-printing
[[ -z "$RAW_OUTPUT" ]] && {
    exec 4> >(uv run "$_DIR"/mdcat.py "$LOGS_FILE" 2>>$LOGS_FILE)
    mdcat_pid=$!
} || exec 4> >(cat -)

SIG_STOP=SIGUSR1
SIG_PLAY=SIGUSR2

while true; do # main loop
    api_completion "$user_prompt"

    kill -$SIG_STOP $mdcat_pid 2>/dev/null && sleep .1
    [[ ! -z "$total_tokens" ]] && [[ -z "$RAW_OUTPUT" ]] && echo -e "\e[38;5;244m$total_tokens tokens\e[0m"
    prompt_user

    kill -$SIG_PLAY $mdcat_pid 2>/dev/null
done
