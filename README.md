# 🪄 agent.sh

tiny terminal agent, written with simplicity and composability in mind.

https://github.com/user-attachments/assets/f53c96da-043c-45af-9b12-0eb7211fef16

## Usage

```bash
cmd1 | chat what should i look for in this
```

```bash
chat "what's a cyclic endomorphism"
```

```bash
chat
```

Flags:

- `--raw` plain output (no markdown rendering), exits after one completion — good for piping: `cmd1 | chat --raw summarize > out.md`
- `--free` skip tool permission prompts

## Install

Make sure to have [uv](https://github.com/astral-sh/uv), [jq](https://github.com/jqlang/jq), [rg](https://github.com/BurntSushi/ripgrep), [bat](https://github.com/sharkdp/bat), [gum](https://github.com/charmbracelet/gum) and [html2text](https://github.com/grobian/html2text) installed

Clone the repo and alias `agent.sh` to a command name of your preference

```bash
alias j='/path/to/agent.sh'
```

Put your provider API keys (if any) in `.env`, see `.env.example`

Pick a provider from `providers/` with the `PROVIDER` env var (default: `opencode-go`)

```bash
PROVIDER=ollama j
```

## Current Capabilities

| Tool          | Description                             |
|---------------|-----------------------------------------|
| **Glob**      | Find files by pattern                   |
| **Grep**      | Search inside files                     |
| **Read**      | Read file                               |
| **Edit**      | Modify file                             |
| **Write**     | Create or append files                  |
| **Bash**      | Run shell commands                      |
| **WebSearch** | Search the web via Exa AI               |
| **WebFetch**  | Fetch URLs with `curl` and `html2text`  |
| **Skill**     | Use specialized skills                  |
| **Question**  | Ask user for input/choices              |

## Slash Commands

- `/state`, `/s`    opens the _state_ which is the json sent to the api in an editor, to inspect it or edit it
- `/continue`, `/c` sends the current _state_ to the API directly
- `/logs`, `/l`     displays logs, which are either outputs of executed tools or reasoning tokens
- `/model`, `/m`    change used model

## Add Capabilities

### Skills

All skills must be placed in `~/.agents/skills/` (customizable via the `SKILL_PATH` env var) in the standard `SKILL.md` format, see `./tools/Skill.sh`.

### Tools

Tools are as simple as Bash functions.  You can check `tools/` directory for
reference, or just ask agent.sh to create it for you!

## Contributions

All contributions are welcome !

## Credits

Thanks to [opencode](https://github.com/anomalyco/opencode) - borrowed a lot of cool ideas from it!
