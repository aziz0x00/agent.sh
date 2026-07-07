#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["rich"]
# ///

import os, signal, select, sys
from rich.live import Live
from rich.markdown import Markdown, TextElement, MarkdownContext
from rich.text import Text
from rich.theme import Theme
from rich.console import Console, ConsoleOptions, RenderResult
from rich.padding import Padding
from markdown_it.token import Token


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
class Heading(TextElement):
    """A heading."""

    @classmethod
    def create(cls, markdown: Markdown, token: Token):
        return cls(token.tag)

    def on_enter(self, context: MarkdownContext) -> None:
        self.text = Text()
        context.enter_style(self.style_name)

    def __init__(self, tag: str) -> None:
        self.tag = tag
        self.style_name = f"markdown.{tag}"
        super().__init__()

    def __rich_console__(
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


Markdown.elements["heading_open"] = Heading


def main():
    console = Console(theme=Theme(THEME))
    console.width = min(console.width, 100)  # fit width

    markdown_text = ""
    buffer_size = 4096
    timeout = 0.05  # Timeout for select in seconds

    with Live(console=console, auto_refresh=True, refresh_per_second=5) as live:
        while resume:
            # Wait for input
            rlist, _, _ = select.select([sys.stdin], [], [], timeout)
            if sys.stdin in rlist:
                chunk = os.read(sys.stdin.fileno(), buffer_size)
                if not chunk:
                    break  # EOF reached
                markdown_text += chunk.decode("utf-8", errors="replace")
                md = Markdown(markdown_text, code_theme="ansi_dark", hyperlinks=False)
                # 1 line top/bottom, 2 spaces left/right
                live.update(Padding(md, (1, 2)))


STOP_SIG = signal.SIGUSR1
PLAY_SIG = signal.SIGUSR2

if __name__ == "__main__":
    resume = True
    "--once" in sys.argv[1:] and exit(main())

    logfile = None
    if len(sys.argv) >= 2:
        logfile = open(sys.argv[1], "a")

    def _handle(signum, _):
        global resume
        resume = signum == PLAY_SIG

    signal.signal(STOP_SIG, _handle)
    signal.signal(PLAY_SIG, _handle)

    while True:
        logfile and logfile.write("\n[P]\n") and logfile.flush()
        main()
        logfile and logfile.write("\n[S]\n") and logfile.flush()
        while not resume:
            signal.pause()
