# prompt_probe

A manual debugging tool for tide's async render path. It runs an interactive
fish in a pty, types at it, resizes it, and prints what landed on the screen —
optionally with a log of every prompt render, background dispatch and signal
handler run.

Nothing here is wired into `mise run test` or CI. The littlecheck tests in
`tests/` are the automated check; this is for the bugs those tests can't see
until you know what to assert.

```fish
python3 scripts/prompt_probe/probe.py --trace 'raw:false\nsleep 1\n'
```

## Why a pty

The prompt is drawn by a real terminal loop reacting to keystrokes, window
size changes and SIGUSR1 from background render jobs. Calling `fish_prompt`
from a script tells you what one render prints; it tells you nothing about
*when* fish renders, how many times, or what state it had at that moment. Most
staleness bugs live in that ordering:

- a render job finishing while a command is still running, so fish handles the
  signal a second later than you'd expect
- two renders in flight at once, because you pressed Enter before the first
  finished
- a window resize fish only notices after the foreground command exits

## What it does

1. Copies this working copy's `functions/` and `conf.d/` into an isolated
   `$HOME` (`$XDG_CACHE_HOME/tide-prompt-probe-home`, or `~/.cache/…`), and
   seeds a small prompt config the first time. Your real fish config is never
   touched or read. The copy is refreshed on every run, so you always probe
   the code you have checked out.
2. Starts `fish -i` under a pty, and answers the terminal capability questions
   fish 4.x asks at startup. Skip that and fish waits for replies that never
   come, printing no prompt at all.
3. Runs your steps in order, reading output as it goes.
4. Prints the transcript with escape sequences stripped, and each step marked
   `<<< like this >>>`.

The seeded config uses plain words instead of glyphs, so the transcript can be
grepped: `OK` / `FAIL 1` for the status item, `DUR 1.02s` for cmd_duration,
plus the working directory. Pass `--items 'status pwd vcs'` to change the item
list.

Items beyond those three need colour and icon variables the seed doesn't set,
and will print errors instead of rendering. To get a full set, configure the
probe `$HOME` once:

```fish
python3 scripts/prompt_probe/probe.py --shell   # then: tide configure
```

`--shell` hands your terminal to the isolated fish, which is also the easiest
way to poke at the prompt by hand — type, resize the window, run a
full-screen program — without installing anything into your own config. The
probe `$HOME` persists between runs, so configure it once; `--reset` wipes it.

Add `--trace` to log an interactive session. Nothing can print the log after
handing over the terminal, so the probe prints its path instead; watch it from
a *second* terminal, or read it afterwards:

```fish
python3 scripts/prompt_probe/probe.py --shell --trace
tail -f ~/.cache/tide-prompt-probe-home/render.log   # from another terminal
```

Watching from inside the traced shell would log your own `tail` and muddy what
you are reading.

## Steps

| Step | What it does |
| --- | --- |
| `sleep 1; false` | types the line, presses Enter, then reads for `--settle` seconds |
| `cmd:CMD` | the same, for a command that would otherwise look like another step |
| `raw:TEXT` | writes TEXT as-is, `\n` included, then reads for `--settle` seconds |
| `keys:TEXT` | writes TEXT as-is, then reads for 0.2s — use before `wait`/`resize` |
| `wait:2` | just reads for 2 seconds |
| `resize:90` | resizes to 90 columns and signals fish, so it notices at once |
| `resizequiet:70` | resizes without signalling fish |

`raw:` is how you get two commands into fish's input buffer at once, so the
second starts while the first prompt's render is still in flight — the easiest
way to reproduce an overlap by hand.

`resizequiet:` is what a full-screen program looks like. During a foreground
command fish isn't in the terminal's foreground process group, so it gets no
SIGWINCH and only learns the new size once the command exits — a different
code path from a resize at the prompt, and one that used to leave the prompt
stale.

## Reading `--trace`

`--trace` rewrites the prompt in the probe's copy of tide, adding a log line
per event:

```
1784950146.652 PROMPT argv='' repaint= cycle=1     <- fish asked for a prompt
1784950146.665   dispatch: pid=57605 cycle=1       <- a background render started
1784950146.679   handler: reading pid=57605 …      <- its result arrived
1784950146.691 PROMPT argv='' repaint=1 cycle=1    <- the repaint it asked for
```

What to look for:

- **A gap between `dispatch` and `handler`** longer than a render takes means
  fish sat on the signal — it was running a foreground command.
- **`repaint=` matching `cycle=`** on a prompt means that render deliberately
  skipped starting a job, because it is the repaint the handler asked for. A
  match at the *start* of a new cycle would be a bug: that prompt paints
  pre-command content.
- **Two `dispatch` lines with no `handler` between them** means renders
  overlapped, so one job is about to be superseded.
- **A `handler` line with `lines=0`** means the newest job hasn't published
  yet and the signal came from a straggler.

Timestamps cost a `perl` fork per line, so tracing perturbs the timing it
measures. Use it to establish ordering, not to benchmark.

The log lives at `<probe $HOME>/render.log` and is **deleted at the start of
every run**, so it only ever holds the latest one — copy it elsewhere to keep
it. Every run also resyncs `functions/` from the repo, which removes the trace
patch, so `--trace` belongs on the run you actually want traced: a run without
it leaves an unpatched prompt that logs nothing.

## Recipes

```fish
# two commands at once: the second starts while a render is in flight
python3 scripts/prompt_probe/probe.py --trace 'raw:false\nsleep 3\n'

# resize while a command runs, then again after
python3 scripts/prompt_probe/probe.py 'keys:sleep 3\n' 'wait:0.5' 'resize:90' 'wait:3'

# what a full-screen program does: size changes, fish finds out afterwards
python3 scripts/prompt_probe/probe.py 'keys:sleep 3\n' 'wait:0.5' 'resizequiet:70' 'wait:3'

# leave a slow repo render behind by cd-ing straight out of it
# (needs a configured probe $HOME for the vcs item -- see above)
python3 scripts/prompt_probe/probe.py --items 'status cmd_duration pwd vcs' \
    "raw:cd $PWD\ncd /tmp\n"
```

After each one, check the last prompt in the transcript against what actually
happened: right exit status, right duration, right directory. A brief wrong
prompt that corrects itself is normal — the prompt is async by design. A wrong
prompt that survives until the next keystroke is the bug.

## When the anchors drift

`--trace` patches `functions/fish_prompt.fish` by matching exact lines. Change
those lines and the probe exits with the anchor it wanted and how many times it
found it. Fix `TRACE_PATCHES` in `probe.py`; don't work around it, since a
silently unpatched prompt logs nothing and looks like "no renders happened".
