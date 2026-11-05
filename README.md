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

The Xcode project file is generated. Change `App/project.yml`, then regenerate.
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

The Mac app is sandboxed: it sees the folder you pick and nothing else. It serves the
Model Context Protocol on `127.0.0.1:27830/mcp`, behind a key per grant. A grant is a
row in its window: who, what they may do. Tools: `whats_new`, `read_days`, `list_lines`,
`read_photo`, `add_note`, `set_label`, `link_lines`, `write_line`, `choose_name`. Writes
land in the grant's own event file; no grant can touch your lines. Revoke the row and the
key is gone.

`whats_new` is the inbox: what happened since the grant last looked, replies first, then
new lines, lines changed, marks taken back, names chosen. Each look is a receipt that
records how long every event file was, so the next look starts after that count per file
and a line that reaches the Mac late through iCloud is still caught.

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

## Building Margin with Margin

Write about the app in the app, like anything else. A Claude Code session in this
repository reads the notebook through the door, labels those lines `margin` (and `bug`
where it is one), fixes what it can, and says what shipped in the chat. What was decided,
floated or found missing along the way goes on its own page. Nothing in the app knows
this is happening; it is an author with a grant.
