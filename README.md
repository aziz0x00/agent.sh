# 🪄 chat.sh

tiny terminal agent, written with simplicity and composability in mind.


https://github.com/user-attachments/assets/3e956d9b-4917-4306-86a9-c07da6642a30


## Usage

```bash
cmd1 | chat what should i look for in this
```

```bash
chat "what's an cyclic endomorphism"
```

```bash
chat
```

## Install

Make sure to have [uv](https://github.com/astral-sh/uv), [jq](https://github.com/jqlang/jq), [rg](https://github.com/BurntSushi/ripgrep) [bat](https://github.com/sharkdp/bat) and [gum](https://github.com/charmbracelet/gum) installed

Clone the repo, save it somewhere and alias `chat.sh` to a command name of your preference

```bash
alias j='/path/to/chat.sh'
```

Put your providers API keys (if any) in `.env`, see `.env.example`

## Current Capabilites

| Tool          | Description                          |
|---------------|--------------------------------------|
| **Glob**      | Find files by pattern                |
| **Grep**      | Search inside files                  |
| **Read**      | Read file                            |
| **Edit**      | Modify file                          |
| **Write**     | Create or append files               |
| **Bash**      | Run shell commands                   |
| **WebSearch** | Search the web via Exa AI            |
| **Skill**     | Use specialized skills               |
| **Question**  | Ask user for input/choices           |



## Slash Commands

- `/state`, `/s`    opens the _state_ which is the json sent to the api in an editor, to inspect it or edit it
- `/continue`, `/c` sends the current _state_ to the API directly
- `/logs`, `/l`     displays logs, which are either outputs of executed tools or reasoning tokens
- `/model`, `/m`    change used model


## Add Capabilities

### Skills

All skills must be placed in `~/.agents/skills/` (customized by `SKILL_PATH` env var) in the standard `SKILL.md` format, see `./tools/Skill.sh`.

### Tools

You can add tools to chat.sh with tool files in the `tools/` directory.

A tool `Foo.sh` file should be in the following format:

```bash
TOOL_DEF='{
  "name": "Foo",
  "description": "tool description",
  "parameters": {
    --- parameter spec ---
  }
}'

## @output either:
# - noerror+json: {fmt: string, preview: string, nextArgs: [string]}
# - error+string: output will be immediately sent back to model (e.g. file doesn't exist)
function PreFoo {
  parameters=$(jq '
  .param = (.param // "default_value")
' <<<"$1") # set defaults

  jq -n --arg preview "$preview" '{
    fmt: "param=" + .param,
    preview: $preview,
    nextArgs: [.param]
  }' <<<"$parameters"
}

## @params: nextArgs from PreFoo
function Foo {
  param=$1
  # do stuff and write result to stdout
}
```

Check available tools and `./tools/0-TEMPLATE.sh` for reference

For now you can put your system prompt in `system_prompt.md` (the current one needs improvements)..
> what I imagine a better improvement is to have agents, and each agents has it's own system prompt and additional settings


## TODO

- make it more useful (subagents, context compaction, ...)
- shorter and smaller code base
- improve code simplicity and readability
- add other providers later if needed

## Credits

Thanks to [opencode](https://github.com/anomalyco/opencode) - borrowed a lot of cool ideas from it!
