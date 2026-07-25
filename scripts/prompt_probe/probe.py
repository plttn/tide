#!/usr/bin/env python3
"""Drive tide's prompt in a real interactive fish, inside a pty.

A manual debugging tool for the async render path -- staleness, missed
repaints, background-job races. Not part of `mise run test`.

See README.md in this directory for what it does and how to read its output.
"""

import argparse
import fcntl
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Legible stand-ins for tide's glyphs, so the transcript can be grepped:
# `OK`/`FAIL 1` for the status item, `DUR 1.02s` for cmd_duration.
SEED_CONFIG = """
set -U tide_left_prompt_items status cmd_duration pwd
set -U tide_right_prompt_items
set -U tide_prompt_add_newline_before false
set -U tide_left_prompt_frame_enabled false
set -U tide_right_prompt_frame_enabled false
set -U tide_prompt_min_cols 1
set -U tide_prompt_pad_items false
set -Ux tide_status_icon OK
set -Ux tide_status_icon_failure FAIL
set -U tide_status_bg_color normal
set -U tide_status_bg_color_failure normal
set -Ux tide_cmd_duration_icon DUR
set -Ux tide_cmd_duration_threshold 100
set -Ux tide_cmd_duration_decimals 2
set -U tide_cmd_duration_bg_color normal
set -U tide_pwd_icon ''
set -U tide_pwd_icon_home ''
set -U tide_pwd_icon_unwritable ''
set -U tide_pwd_bg_color normal
"""

# `--trace` rewrites the prompt in the probe's own copy of tide, so every
# render, dispatch and signal handler run lands in a log with a timestamp.
# Each anchor must match exactly as many times as stated, so this fails
# loudly when fish_prompt.fish moves rather than tracing nothing.
LOG_FUNCTION = """function _tide_probe_log
    set -l stamp (command perl -MTime::HiRes -e 'printf "%.3f", Time::HiRes::time()' 2>/dev/null)
    test -n "$stamp" || set stamp (command date +%s)
    command printf '%s %s\\n' $stamp "$argv" >>@LOG@
end

"""

TRACE_PATCHES = [
    (
        1,
        "set_color normal | read -l color_normal",
        LOG_FUNCTION + "set_color normal | read -l color_normal",
    ),
    (
        1,
        "    set -l rendered (cat $_tide_prompt_tmpfile.$_tide_last_pid 2>/dev/null)",
        "    set -l rendered (cat $_tide_prompt_tmpfile.$_tide_last_pid 2>/dev/null)\n"
        '    _tide_probe_log "  handler: reading pid=$_tide_last_pid lines="(count $rendered)" cycle=$_tide_cycle"',
    ),
    (
        1,
        "    set -g _tide_last_pid $last_pid",
        "    set -g _tide_last_pid $last_pid\n"
        '    _tide_probe_log "  dispatch: pid=$last_pid cycle=$_tide_cycle"',
    ),
    (
        2,
        "    set -lx _tide_status \\$status\n    _tide_pipestatus=\\$pipestatus if test",
        "    set -lx _tide_status \\$status\n"
        "    set -l _tide_probe_ps \\$pipestatus\n"
        "    _tide_probe_log \\\"PROMPT argv='\\$argv' repaint=\\$_tide_repaint cycle=\\$_tide_cycle\\\"\n"
        "    _tide_pipestatus=\\$_tide_probe_ps if test",
    ),
]

ESCAPES = [
    re.compile(r"\x1b\[[0-9;?>]*[a-zA-Z]"),
    re.compile(r"\x1b[\]P][^\x07\x1b]*(\x07|\x1b\\)?"),
    re.compile(r"\x1b[()][B0]"),
    re.compile(r"\x1b[=>]"),
]


def probe_home():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "tide-prompt-probe-home"


def build_home(args):
    """Sync this working copy of tide into an isolated, reusable $HOME."""
    home = probe_home()
    config = home / ".config" / "fish"

    if args.reset:
        shutil.rmtree(home, ignore_errors=True)

    fresh = not (config / "fish_variables").exists()
    config.mkdir(parents=True, exist_ok=True)

    # Always resync, so the probe runs whatever is checked out right now.
    for name in ("functions", "conf.d"):
        shutil.rmtree(config / name, ignore_errors=True)
        shutil.copytree(REPO / name, config / name)

    log = home / "render.log"
    log.unlink(missing_ok=True)
    if args.trace:
        patch_prompt(config / "functions" / "fish_prompt.fish", log)

    seed = SEED_CONFIG if fresh else ""
    if args.items:
        seed += f"\nset -U tide_left_prompt_items {args.items}\n"
    if seed:
        run_fish(home, seed)

    return home, log


def patch_prompt(path, log):
    source = path.read_text()
    for expected, anchor, replacement in TRACE_PATCHES:
        found = source.count(anchor)
        if found != expected:
            sys.exit(
                f"--trace: expected {expected} occurrence(s) of this anchor in "
                f"{path.name}, found {found}. The prompt has changed; update "
                f"TRACE_PATCHES in {Path(__file__).name}.\n  anchor: {anchor!r}"
            )
        replacement = replacement.replace("@LOG@", str(log))
        source = source.replace(anchor, replacement)
    path.write_text(source)


def run_fish(home, script):
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))
    env.pop("XDG_CACHE_HOME", None)
    result = subprocess.run(
        ["fish", "-c", script], env=env, capture_output=True, text=True
    )
    if result.returncode != 0:
        sys.exit(f"config setup failed:\n{result.stderr}")


def spawn(home, cols, lines, cwd):
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))
    env["TERM"] = "xterm-256color"
    env.pop("XDG_CACHE_HOME", None)

    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd or str(home))
        os.execvpe("fish", ["fish", "-i"], env)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", lines, cols, 0, 0))
    return pid, fd


class Session:
    def __init__(self, pid, fd):
        self.pid, self.fd = pid, fd
        self.out = []

    def drain(self, seconds):
        end = time.time() + seconds
        while True:
            left = end - time.time()
            if left <= 0:
                return
            ready, _, _ = select.select([self.fd], [], [], left)
            if not ready:
                continue
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return
            if not data:
                return
            # fish 4.x asks the terminal what it can do and waits for the
            # replies. A bare pty never answers, so stand in for a terminal
            # -- without this fish blocks at startup and prints no prompt.
            if b"\x1b]11;?" in data:
                os.write(self.fd, b"\x1b]11;rgb:0000/0000/0000\x1b\\")
            if b"\x1b[0c" in data:
                os.write(self.fd, b"\x1b[?62;22c")
            self.out.append(data.decode("utf8", "replace"))

    def send(self, text):
        os.write(self.fd, text.encode())

    def resize(self, cols, lines, notify):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", lines, cols, 0, 0))
        if notify:
            os.kill(self.pid, signal.SIGWINCH)

    def mark(self, text):
        self.out.append(f"\n<<< {text} >>>\n")

    def transcript(self):
        text = "".join(self.out)
        for pattern in ESCAPES:
            text = pattern.sub("", text)
        return text.replace("\r", "")


def run_steps(session, steps, settle, lines):
    for step in steps:
        kind, _, value = step.partition(":")
        if kind == "wait":
            session.drain(float(value))
            continue
        if kind in ("resize", "resizequiet"):
            session.mark(step)
            session.resize(int(value), lines, notify=kind == "resize")
            session.drain(0.2)
            continue

        session.mark(step)
        if kind == "raw":
            session.send(value.replace("\\n", "\n"))
            session.drain(settle)
        elif kind == "keys":
            session.send(value.replace("\\n", "\n"))
            session.drain(0.2)
        else:
            session.send((value if kind == "cmd" else step) + "\n")
            session.drain(settle)


def main():
    parser = argparse.ArgumentParser(
        description="Drive tide's prompt in an interactive fish inside a pty.",
        epilog="steps: CMD | cmd:CMD | raw:TEXT | keys:TEXT | wait:SECONDS | "
        "resize:COLS | resizequiet:COLS  (see README.md)",
    )
    parser.add_argument("steps", nargs="*", help="what to do, in order")
    parser.add_argument("--items", help='value for tide_left_prompt_items, e.g. "status pwd vcs"')
    parser.add_argument("--trace", action="store_true", help="log every render, dispatch and handler run")
    parser.add_argument("--settle", type=float, default=2.5, help="seconds to read after a command (default 2.5)")
    parser.add_argument("--cols", type=int, default=100)
    parser.add_argument("--lines", type=int, default=40)
    parser.add_argument("--cwd", help="directory to start fish in (default: the probe $HOME)")
    parser.add_argument("--reset", action="store_true", help="delete the probe $HOME and reseed its config")
    parser.add_argument(
        "--shell",
        action="store_true",
        help="hand over to the isolated fish instead of running steps, e.g. to run `tide configure` in it",
    )
    args = parser.parse_args()

    if not (REPO / "functions" / "fish_prompt.fish").exists():
        sys.exit(f"cannot find tide's functions/ under {REPO}")

    home, log = build_home(args)

    if args.shell:
        print(f"=== probe $HOME: {home}")
        if args.trace:
            # Nothing prints the log after an exec, and watching it from
            # inside the traced shell would log the watching itself.
            print(f"=== render log: {log}")
            print(f"=== watch it from another terminal: tail -f {log}")
        print("=== exit the shell to come back")
        # exec replaces this process, so anything still sitting in Python's
        # stdout buffer would never be written.
        sys.stdout.flush()
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))
        env.pop("XDG_CACHE_HOME", None)
        os.chdir(args.cwd or str(home))
        os.execvpe("fish", ["fish", "-i"], env)

    pid, fd = spawn(home, args.cols, args.lines, args.cwd)
    session = Session(pid, fd)

    session.drain(2.0)
    run_steps(session, args.steps, args.settle, args.lines)
    session.drain(1.0)
    session.send("exit\n")
    session.drain(1.0)

    print(f"=== probe $HOME: {home}")
    print("=== transcript")
    print(session.transcript())
    if args.trace:
        print("=== render log")
        print(log.read_text() if log.exists() else "(empty -- no renders logged)")


if __name__ == "__main__":
    main()
