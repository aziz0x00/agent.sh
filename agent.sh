#!/bin/bash

# ---------- config ----------
_DIR=$(dirname "${BASH_SOURCE[0]}")

while true; do
    case "$1" in
    --raw) RAW_OUTPUT=true && shift ;;
    --free) BYPASS_PERMS=true && shift ;;
    *) break ;;
    esac
done

TMP_BASE=$(mktemp -u)
STATE_FILE=$TMP_BASE.json
LOGS_FILE=$TMP_BASE.log

SIG_STOP=SIGUSR1 # pause mdcat rendering (see mdcat.py)
SIG_PLAY=SIGUSR2 # resume it
MAX_OUTPUT=40000 # truncate tool output beyond this

set -a
source "$_DIR"/.env
set +a # populate env

C_DIM=${C_DIM:-'\e[38;5;244m'} # colors are overridable from .env
C_OFF='\e[0m'
GUM_DIM=${GUM_DIM:-'#93a1a1'}
GUM_OK=${GUM_OK:-'#34d399'}
GUM_WARN=${GUM_WARN:-'#e5c07b'}

shopt -s lastpipe # because curl | while

# ---------- bootstrap ----------
function jq_inplace { jq "$@" <"$STATE_FILE" >"$STATE_FILE".tmp && mv "$STATE_FILE".tmp "$STATE_FILE"; }

source "$_DIR"/providers/"${PROVIDER:-opencode-go}".sh

switch_model "${MODELS[0]}"

add_system_prompt "$(cat "$_DIR"/system_prompt.md)"
add_system_prompt "Current date: $(date "+%a %b %d %Y")"

declare -A TOOLS ALLOWED_TOOLS SAFE_TOOLS=([Skill]=1 [WebSearch]=1 [Question]=1) # TODO: do better tool perms mgmt
for tool in Question Read Glob Grep WebSearch Skill Edit Write Bash; do
    source "$_DIR"/tools/$tool.sh
    TOOLS[$tool]=$TOOL_DEF
done && activate_tools TOOLS

touch "$LOGS_FILE" && [[ -n "$TMUX_PANE" ]] &&
    tmux splitw -dv -l 5 "echo -e '${C_DIM}LOGS($LOGS_FILE)'; tail -f $LOGS_FILE"

# ---------- ui ----------
function prompt_user {
    [[ -n "$RAW_OUTPUT" ]] && exit
    while true; do
        local width=$(($(tput cols) - 2)) && ((width > 80)) && width=80
        user_prompt=$(gum write --width $width --height=3 --header="$model" </dev/tty)
        [[ $? -eq 130 ]] && exit # ^C
        [[ -z "$user_prompt" ]] && continue
        [[ $width -gt ${#user_prompt} ]] && width=0

        case "$user_prompt" in
        /s | /state) ${EDITOR:-vim} "$STATE_FILE" ;;
        /c | /continue) user_prompt="" && return ;; # useful after manual modification by /s
        /l | /logs) less "$LOGS_FILE" ;;
        /m | /model) switch_model $(echo "${MODELS[@]}" | gum choose --input-delimiter=" ") &&
            echo -e "${C_DIM}switched to $model$C_OFF" ;;
        *)
            gum style --width $width --margin '0 0' --border=rounded --padding="0 1" "$user_prompt"
            return
            ;;
        esac
    done
}

# asks for confirmation unless pre-allowed; returns nonzero on denial
function __approve_tool {
    local funcname=$1 fmt=$2 label=$3
    [[ "$BYPASS_PERMS" == "true" ]] && return
    [[ -n "${ALLOWED_TOOLS[$fmt]}${SAFE_TOOLS[$funcname]}" ]] && return

    local sound_pid
    [[ -f "$NOTIFICATION_SOUND" ]] && { # delayed alert
        (
            sleep 5
            ffplay -nodisp -autoexit -volume 70 "$NOTIFICATION_SOUND" &>/dev/null
        ) &
        sound_pid=$!
    }

    local prompt=$(gum style "$label" --foreground "$GUM_WARN")$'\n\n Approve invocation?'
    local answer=$(echo -e "Yes\nYes, always allow this signature\nNo, adjust approach" |
        gum choose --header="$prompt")

    [[ -n "$sound_pid" ]] && [[ "$sound_pid" == "$(jobs -rp | tail -1)" ]] && kill $sound_pid &>/dev/null

    case "$answer" in
    Yes) ;;
    "Yes, always"*)
        ALLOWED_TOOLS[$fmt]=1
        echo "Tool allowed: $fmt" >>"$LOGS_FILE"
        ;;
    *) return 1 ;;
    esac
}

# ---------- tool dispatch ----------
function tool_call {
    local funcname=$1 parameters=$2
    declare -n result=$3

    mdcat_pause

    [[ -z "${TOOLS[$funcname]}" ]] && result="Tool unavailable." && return

    local output
    output=$(Pre$funcname "$parameters")
    [[ $? -ne 0 ]] && result="$output" && return # validation errors go straight back to the model

    printf '%s>\n%s\n'"$C_DIM"'<%s\n' "$funcname" "$(jq -r .preview <<<"$output")" "$funcname" >>"$LOGS_FILE"

    local fmt=$(jq -c -r .fmt <<<"$output")
    local label="$(gum style "  › $funcname" --bold) $(gum style "$fmt" --foreground "$GUM_DIM")"

    if __approve_tool "$funcname" "$fmt" "$label"; then
        gum style "$label" --foreground "$GUM_OK" >/dev/tty
        local nextArgs=()
        jq -c '.nextArgs[]' <<<"$output" | while read -r line; do
            nextArgs+=("$(jq -r '.' <<<"$line")")
        done
        result=$($funcname "${nextArgs[@]}" | tee -a "$LOGS_FILE")
        [[ ${#result} -gt $MAX_OUTPUT ]] &&
            result=$(head -c $MAX_OUTPUT <<<"$result")"(truncated, $((${#result} - MAX_OUTPUT)) remaining)"
    else
        gum style "$label" --foreground "$GUM_WARN" --faint >/dev/tty
        prompt_user
        result="<user_interrupted>$user_prompt</user_interrupted>"
    fi

    mdcat_resume
}

# ---------- plumbing ----------
function mdcat_pause { kill -$SIG_STOP $mdcat_pid 2>/dev/null && sleep .1; } # it can lag behind the stream
function mdcat_resume { kill -$SIG_PLAY $mdcat_pid 2>/dev/null; }

function __consume_pipe {
    local input=$(mktemp)
    cat - >"$input"
    if [[ $(file -b --mime-type "$input") =~ image ]]; then
        set_attachments "$input"
    else
        user_prompt=$user_prompt$'\n\n---\n\n'"$(cat "$input")"
    fi
    rm "$input"
}

function clean_exit {
    fuser --kill "$LOGS_FILE" &>/dev/null # stops the log pane's tail
    rm -f "$TMP_BASE"*
    kill -9 $mdcat_pid 2>/dev/null
    exit
}
trap clean_exit EXIT
trap '[[ -z "$user_prompt" ]] && clean_exit' INT # to interrupt generation and go back to prompt

# ---------- main ----------
user_prompt=$*
[[ $# -eq 0 ]] && prompt_user
[[ -p /dev/stdin || -f /dev/stdin ]] && __consume_pipe # should be after prompt_user

if [[ -z "$RAW_OUTPUT" ]]; then # mdcat pretty-prints the stream written to fd 4
    exec 4> >(uv run "$_DIR"/mdcat.py "$LOGS_FILE" 2>>"$LOGS_FILE")
    mdcat_pid=$!
else
    exec 4> >(cat -)
fi

while true; do
    SECONDS=0
    api_completion "$user_prompt"

    status=$SECONDS
    mdcat_pause
    [[ -n "$total_tokens" ]] && status="${status}s · ${total_tokens} tok"
    [[ -z "$RAW_OUTPUT" ]] && echo -e "$C_DIM$status$C_OFF"
    prompt_user
    mdcat_resume
done
