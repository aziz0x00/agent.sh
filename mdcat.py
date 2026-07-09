#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["rich"]
# ///

import os, sys
from rich.live import Live
from rich.markdown import Markdown
from rich.text import Text
from rich.theme import Theme
from rich.console import Console, ConsoleOptions, RenderResult
from rich.padding import Padding


THEME = {
    "markdown.h1": "bold #2e3440 on #88c0d0",
    "markdown.h2": "bold #81a1c1",
    "markdown.h3": "bold #88c0d0",
    "markdown.h4": "bold #8fbcbb",
    "markdown.h5": "bold #a3be8c",
    "markdown.h6": "bold #b48ead",
    "markdown.text": "#d8dee9",
    "markdown.strong": "bold #eceff4",
    "markdown.emphasis": "italic #b48ead",
    "markdown.code": "#88c0d0 on #3b4252",
    "markdown.code_block": "on #2e3440",
    "markdown.link": "#8fbcbb underline",
    "markdown.block_quote": "italic #d08770",
    "markdown.list": "#d8dee9",
    "markdown.item": "#d8dee9",
    "markdown.item.bullet": "#b48ead",
    "markdown.item.number": "#ebcb8b",
    "none": "#d8dee9",
    "markdown.hr": "#4c566a",
}


# inspired from the cool https://github.com/charmbracelet/glow
def custom_rich_console(
    self, console: Console, options: ConsoleOptions
) -> RenderResult:
    text = self.text
    if self.tag == "h1":
        text.style = ""
        text.end = ""
        yield Text(" ", style="markdown.h1", end="")
        yield text
        yield Text(" ", style="markdown.h1")
    else:
        yield Text("#" * (int(self.tag[1:])) + " ", end="", style=self.style_name)
        yield text


Markdown.elements["heading_open"].__rich_console__ = custom_rich_console


def main():
    console = Console(theme=Theme(THEME))
    console.width = min(console.width, 100)  # fit width

    markdown_text = ""

    with Live(console=console, auto_refresh=True, refresh_per_second=1) as live:
        while True:
            chunk = os.read(sys.stdin.fileno(), 4096)
            if not chunk:
                break  # EOF: agent.sh closed fd 4, leaving Live commits the render
            markdown_text += chunk.decode("utf-8", errors="replace")
            md = Markdown(markdown_text, code_theme="ansi_dark", hyperlinks=False)
            # 1 line top/bottom, 2 spaces left/right
            live.update(Padding(md, (1, 2)))


if __name__ == "__main__":
    main()
