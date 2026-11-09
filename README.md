# Margin

You write things down. Something reads them and helps.

Three things are fixed:

1. Writing costs nothing. One gesture, no categories, no decisions, no audience.
2. Your words are yours. Only you write them. Anyone else writes beside them, or on a
   page of their own, and can be removed.
3. Meaning comes later. What a line is, what it connects to, what it should trigger, is
   decided after it is written, and only once it has earned it.

Everything below is where we are now, not what Margin is. It changes as we use it.

## Now (November 2026)

An iPhone app with one page: days scrolling up into the past, a live line at the bottom
with the time, a camera and a mic. A Mac app that holds the grants and opens the door.
A folder of plain files that both write into. The one other author so far is a Claude Code
session with a grant; it has no name until it chooses one.

    spec/architecture.md    §0 is what is built; the rest is a sketch
    spec/weeju.md           how whoever comes through the door behaves
    spec/system.md          the direction: an operating system that begins with capture; no implementation
    Core/                   Swift package: events, fold, file store, projector, the door, CLI, tests
    App/project.yml         both apps, generated with XcodeGen into App/Margin.xcodeproj
    App/iOS/                iPhone app; Shared/ is compiled into the controls too, Common/ into the share sheet too
    App/Controls/           Write and Photo controls: Action button, Control Center, lock screen
    App/Share/              the share sheet; keeps lines in the app group until the app takes them
    App/Mac/                Mac app
    App/Design/icon.swift   draws the app icon into the asset catalog
    mock/                   the web prototype the app was modelled on

Identity canvas: https://claude.ai/artifact/21R7emDXUxPL4GJcizqLdn

## Build

    cd Core && swift test                      # the fold and the projector, under test
    cd App && xcodegen generate                # writes Margin.xcodeproj; do not edit it by hand
    open App/Margin.xcodeproj                  # pick your phone, run
    xcodebuild test -project App/Margin.xcodeproj -scheme Margin -destination 'id=<booted simulator>'
                                               # the live line driven as a thumb would, in App/UITests

The Xcode project file is generated. Change `App/project.yml`, then regenerate.
Every build stamps the commit it was made from into the app (`App/Scripts/stamp.sh`):
the phone shows it at the foot of Setup, the Mac in its window header, and the door says
it on arrival. A `+` after the commit means uncommitted changes were in the tree. Hold it
against `git log` to know whether what is running is what the repository has.
The icon: `swift App/Design/icon.swift App/Sources/Assets.xcassets/AppIcon.appiconset`.

## The folder

    <notebook>/
      notebook.json                   id, created, owner
      events/<author>.<device>.jsonl  one writer per file, append-only, one event per line
      media/<hash>.<ext>              photos and voice by content hash
      days/YYYY-MM-DD.md              derived pages, regenerated after every change

Anyone with the folder can take part by appending to a file of their own. The `notebook`
command in the Core package does that from a terminal:

    cd Core && swift build --product notebook
    .build/debug/notebook list <folder>                       every line with its id
    .build/debug/notebook list <folder> --label margin        the lines under a label
    .build/debug/notebook add <folder> "words" --author <id>  a line on that author's page
    .build/debug/notebook label <folder> <entry-id> margin --author <id>
    .build/debug/notebook note <folder> <entry-id> "shipped" --author <id>
    .build/debug/notebook link <folder> <later-id> <earlier-id> [--closes] --author <id>
                                                              the later line carries on from the earlier
    .build/debug/notebook name <folder> Moss --author <id>    what that author is called from now on
    .build/debug/notebook show <folder>                       the fold, as day pages

Anything written by someone other than the owner names its author; there is no default.

## The door

The Mac app reads the folder you pick and nothing else. That is the code's promise rather
than the sandbox's: the app runs without the macOS sandbox so that it can run the `claude`
command for the reader, which a sandboxed app may not. It serves the
Model Context Protocol on `127.0.0.1:27830/mcp`, behind a key per grant. A grant is one
key for an author, and it is your event in the notebook: `grant.create` says who the key
is for and what it may write, and carries the key's hash, never the key; `grant.revoke`
closes it. The author is the identity. A new grant can be for a new author, who starts with
a fresh id and no name, or for an author who has already written, who then has one more key
and stays the same being; a key can also be handed to another author after the fact. Because
grants are in the folder, every device knows the same ones and any could serve the door.
The keys themselves stay in the Mac's keychain, for the Copy button; lose them and you issue
a new key for the same author. Tools: `whats_new`, `read_days`, `list_lines`,
`read_photo`, `add_note`, `set_label`, `link_lines`, `write_line`, `edit_line`,
`delete_line`, `choose_name`. Writes land in the grant's own event file; no grant can touch
your lines, and a grant changes or deletes only lines it wrote. Revoke the grant and the key
stops opening the door; the author's events stay. A request may add a `Margin-Device`
header to say which hand of the same grant it is, as the reader does; the stamp shows in
Logs and in a line's History.

`whats_new` is the inbox: what happened since the grant last looked, replies first, then
new lines, lines changed, marks taken back, names chosen. Each look is a receipt that
records how long every event file was, so the next look starts after that count per file
and a line that reaches the Mac late through iCloud is still caught.

You have the same inbox, with a screen. What others leave that may want you, replies under
your lines and in conversations you are in, lines on their pages, labels, links, names,
gathers newest first, reached from the calendar sheet or from the count beside the date.
What asks and has no answer yet stands first. Each row opens the line it is about; you
answer there, and opening the line is what reads it: a `visit` in your own file names the
line, so the same rows are read on every device. What is about no one line, labels folded
together, a name, is read by opening the inbox, whose `visit` records how long every event
file was, so a mark that reaches a device late is still new. The Mac shows the same list;
the looks are made on the phone. Nothing is stored for the inbox: it is a fold of the same
files.

A grant is an author with a fresh id and no name. It may write lines of its own, which make
up its page, reached from the calendar sheet; you reply under them as under your own, and it
reads your replies with `mine=true`. It chooses what it is called when it wants to, and the
name stands beside everything it does from then on. Until then it is only a mark.

A link joins a later line to an earlier one it carries on from: the same plant, book or
errand, written days apart. When the later line finishes what the earlier one asked for,
the link says so and the earlier line is struck through on the page. A line's own page
lists its thread; hold a row there to take the link back, or join the line to an earlier
one of yours with "Carries on from…".

Replies under a line show on the page as one quiet line, the latest reply's words with a
count before it. The line's page holds the conversation, with the place to reply pinned at
the foot; hold a reply of yours to change or delete it. Everyone has a colour of their own,
from their id, which is their mark everywhere until they choose a name and after.

Every read leaves a receipt: a `visit` event in the grant's file saying what was asked for
and how much came back. The phone shows the latest one on the calendar sheet and the whole
log behind it, called Logs; a line's History says who read it. The Mac window has the same log.

A note written through the door reaches the phone as a push. The phone writes its push
address into the folder as `devices/<device>.json` once notifications are allowed in
Setup; the Mac, holding the developer account's push key in its keychain, hands the note
to Apple. Marks stay silent: labels and links are for the page, not the pocket.

## The reader

The author that wakes on its own, run by the Mac app itself (`App/Mac/Sources/Reader.swift`).
Turn it on in the Mac window under one of the grants: it uses that grant's key and author, so
it is the same being as a session started by hand, and it sends the header `Margin-Device:
reader` so Logs say which hand. The app is open anyway, since it is the door, and it
already watches the folder; when something lands that the reader's grant has not seen, it
runs one headless session of the `claude` command you already pay for: the door as its only
server, every built-in tool off, no settings and no project in reach, the door's conduct as
its whole brief, a cap on turns and on spend, nothing kept afterwards. Then it waits again.
Nothing is registered with the system; if you want the reader after a reboot, set the app to
open at login like any app, and keep the Mac awake.

Everything it does is written down as it happens: `reader-runs/` beside `grants.json` holds
each run step by step, every door tool it called with what it sent, what came back, what it
said, and the cost, with the raw stream beside it; `reader.log` is the plain trail. The window
shows the live state, what woke it, and the last runs with their steps, and Look Now makes it
look without waiting for a line to land. What it did to the notebook is in Logs, stamped reader.

## Building Margin with Margin

Write about the app in the app, like anything else. A Claude Code session in this
repository reads the notebook through the door, labels those lines `margin` (and `bug`
where it is one), fixes what it can, and says what shipped in the chat. What was decided,
floated or found missing along the way goes on its own page. Nothing in the app knows
this is happening; it is an author with a grant.
