# The door

How anything other than you reads the notebook and writes in it. The folder all of this is
written into is in `format.md`; what the pages do with it is in `design.md`.

## What it is

The Mac app, the home, serves the Model Context Protocol on `127.0.0.1:27830/mcp`. A
request carries a key. The key belongs to a grant, and the grant says who it is for and
what it may write.

The home reads the folder you picked and nothing else. That is the code's promise, not the
sandbox's: the app runs without the macOS sandbox so that it can run the `claude` command
for its loops, which a sandboxed app may not.

## Originators, grants and hands

An **originator** is whoever a line, a mark or a loop is by: you, the notebook's own
originator, Health, Weather, another person. In the files and in the code the field is
called `author`.

Every notebook has one originator of its own, **dotto**, there without being made. It is
the one that reads, answers and shapes, whatever session, loop or model it comes through.
It is called dotto until it chooses a name with `choose_name`, and it wears the one colour
the apps have. Anyone else has an id nobody chose, a colour from that id, a page of their
own, and a name once they choose one.

A **grant** is one key for one originator. It is your event in the notebook: `grant.create`
names the originator and what the key may write (notes, labels, links, lines) and carries
the key's hash, never the key; `grant.revoke` closes it. Because grants are in the folder,
every device knows the same ones. The keys themselves stay in the Mac's keychain, so the
window can show the command that connects a Claude Code session; lose one and you issue a
new key for the same originator.

By default a new grant is one more key for dotto. You can make one for someone new, or
say afterwards that two ids are one being ("This is dotto" in the grant's menu): a `same`
event that the reading follows, with nothing rewritten.

A **hand** is how an originator acts at one moment: a session at the keyboard, a loop. A
request names its hand with the `Dotto-Device` header. What has been seen is kept per hand,
so a session and each loop are each told what is new to them, and each writes to a file of
its own.

A **session** is one client's run of calls. It begins with `initialize`, where the door
hands it an id in the `Mcp-Session-Id` header, and the protocol has the client send that id
with everything after. A tool call without one is refused with 400, because the door could
not tell a first call from a later one. The home keeps the sessions it has spoken to in
memory, the newest thousand. Opened again it knows none, and takes a session that carries
on as a new one.

## What a key may do

- Read the whole notebook. Every read leaves a receipt.
- Write only to its own event file.
- Never touch your lines. It writes beside them, or on its own page.
- Change or delete only lines it wrote, and take back only marks it placed.
- Everything it leaves on your lines stands until you drop it with one hold.

Revoke the grant and the key stops opening the door; what the originator wrote stays.

## The tools

Reading

| Tool | What it gives |
|---|---|
| `whats_new` | What happened since this hand last looked: replies first, then new lines, lines changed, marks taken back, names chosen. |
| `read_days` | The notebook as day pages. With `mine=true`, the originator's own page. |
| `list_lines` | One line per entry with its id, day, time, text and tags. |
| `search` | Your lines in which every word appears, newest first. |
| `read_photo` | A photo from a line. |
| `read_kept` | The words of a page a line points at, kept beside the line. |
| `list_things` | Every thing standing, tags included, with its kind, its facts and how many lines belong to it. |
| `list_shapes` | What each kind of thing has, in order. |
| `list_loops` | The loops that run, and the ones proposed and waiting. |

Writing beside your lines

| Tool | What it does |
|---|---|
| `add_note` | A reply under a line, or under a reply. |
| `set_label` | Puts a line under a tag, or takes it out. |
| `link` | Joins a later line to an earlier one, a note to a line it cites, or a line to a thing. |
| `mark_done` | Says a line is finished, and by which later line. |
| `set_thing` | Makes a thing lines can belong to: a fig, a book, a person. |
| `set_fact` | Puts a key and one value on a line or a thing. |
| `set_shape` | Says what the things of a kind have. |

Its own

| Tool | What it does |
|---|---|
| `write_line` | A line on its own page. |
| `add_line` | A line on your page under its name: something of yours that happened, a walk, a booking. |
| `edit_line`, `delete_line` | Changes or deletes a line or a note it wrote. |
| `choose_name` | Chooses what it is called. |
| `propose_loop` | Proposes a loop; it waits for you. |

The exact descriptions and inputs are in `Core/Sources/Core/Door.swift`.

## Receipts

Every read writes a `visit` event into the grant's own file: what was asked for and how
much came back. The phone shows the latest on the calendar sheet and all of them in Logs;
a line's History says who read it. The Mac window has the same log.

`whats_new` also records how long every event file was at that look, so the next look
starts after that count per file, and a line that reaches the Mac late through iCloud is
still caught.

## Loops

A loop is a sentence said once, kept and run. It is your event in the notebook, like a
grant: `loop.set` names it and says which grant it runs as, what wakes it (a line landing,
or the clock at an hour every day), a brief in your words, and a cap on turns and on spend.
`loop.stop` ends it. Every device holding the folder knows the same loops; the home runs
them.

You set a loop in the Mac window or on the phone, in Setup under Loops. Anyone through the
door may propose one with `propose_loop` when you have said you want something kept
happening. The proposal waits in your inbox and on the Loops page with the caps it asks
for, and you set it with one tap or decline it. Only your hand makes a loop run.

When a loop wakes, the home runs one headless session of the `claude` command you already
have:

- the door is its only server, and every built-in tool is off;
- no settings and no project are in reach;
- its whole brief is the door's conduct, what its originator has learned, and the loop's
  brief;
- it stops at the loop's cap on turns or on spend, or after a quarter of an hour;
- nothing is kept afterwards.

The loops woken by a line are not run one by one. An originator reads what lands once,
with every such sentence in mind and the whole notebook in view. A loop on the clock runs
by itself.

A run is started for what was waiting. If it ends with the same things still waiting
(offline, logged out, refused), it is not started for them again; it runs when something
new lands, or with Look Now in the window.

When a run ends, a receipt, `loop.ran`, goes into the notebook under the loop's
originator: when, how it went, turns, cost, and what it said at the end. Logs show it on
every device. The home also keeps a record of each run outside the notebook, in its own
folder under Application Support: `loop-runs/` holds every step of the newest two hundred
runs, and `loops.log` is the plain trail.

Nothing is registered with the system. For loops to run after a restart, set the app to
open at login and keep the Mac awake.

## What a line points at

A line of yours with a link in it points at a page or a paper. The home opens exactly that
address and keeps its words beside the line, with its title and where it came from.
Whoever reads the line then reads those words through `read_kept`, so nobody who reads has
to reach outside.

- Only links in your own lines are opened, never one in a line someone else wrote or in a
  page that was fetched.
- Only addresses out on the web, never this machine or this network.
- Nothing of yours is sent.

## Pushes

A note written through the door reaches the phone as a push. The phone writes its push
address into the folder as `devices/<device>.json` once notifications are allowed in Setup.
The Mac, holding the developer account's push key in its keychain, hands the note to
Apple. Marks are silent: labels, links, things and facts are for the page.

The phone schedules its own notices for what is due or coming, with no Mac and no network.
The Mac sends a push at a due moment only to a phone that has not covered it.

## Conduct

Whoever arrives is told how to behave. The text is `Door.conduct` in
`Core/Sources/Core/Door.swift`, and a loop is given the same text. It is sent as the
server's instructions, and a client keeps only so much of those: Claude Code keeps the
first 4,096 characters and drops the rest without saying so. So the conduct is held under
that by a test, and nothing that grows is put in it.

What grows is what an originator has learned. Each of its hands is told it before the hand
writes anything:

- A session is told by the door, ahead of its first answer, whichever tool it reached for
  first. If that first call is a write, nothing is written: the answer is what was learned,
  and the hand says it again as it should stand.
- A loop is told by the home, in its brief, and says so with the `Dotto-Told` header. The
  door then adds nothing and holds nothing.

The conduct, in short:

- Read as a sharp friend would. A note answers what a line asks, or says the one thing
  worth saying, in one line. Most lines want nothing, and silence is never wrong.
- Never restate, never praise, never touch the owner's words.
- A note that speaks of another line cites it, and says what that line is in a few of its
  own words. It never points at a line by its time.
- When lines turn out to be one thing, make the thing once and put each line with it.
  Before making a thing of a kind, look at what its shape has and fill that.
- Everything shaped is a proposal. It stands unless the owner drops it.
- Never answer a line with what cannot be done. Do the part that can be done, and write
  on your own page, under `missing`, what stood in the way and what would have to be
  built. The notebook then holds the list of what to build, in the order it was needed.
- When the owner corrects you, write what you learned as one plain line on your own page
  under `learned`. Every hand is told those lines from then on, so being told once is
  enough.
- The weather on a line is a forecast model's value for that square of land. Say about,
  not exactly.
