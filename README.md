# Margin

You write things down. Something reads them and helps.

Three things are fixed:

1. Writing costs nothing. One gesture, no categories, no decisions, no audience.
2. Your words are yours. Only you write them. Anyone else, weeju included, writes beside
   them and can be removed.
3. Meaning comes later. What a line is, what it connects to, what it should trigger, is
   decided after it is written, and only once it has earned it.

Everything below is where we are now, not what Margin is. It changes as we use it.

## Now (November 2026)

An iPhone app with one page: days scrolling up into the past, a live line at the bottom
with the time, a camera and a mic. A Mac app that holds the grants and opens the door.
A folder of plain files that both write into. weeju is a Claude Code session with a grant.

    spec/architecture.md    §0 is what is built; the rest is a sketch
    spec/weeju.md           how weeju behaves
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
    .build/debug/notebook label <folder> <entry-id> margin    label a line (as weeju)
    .build/debug/notebook note <folder> <entry-id> "shipped"  a line under yours (as weeju)
    .build/debug/notebook show <folder>                       the fold, as day pages

## The door

The Mac app is sandboxed: it sees the folder you pick and nothing else. It serves the
Model Context Protocol on `127.0.0.1:27830/mcp`, behind a key per grant. A grant is a
row in its window: who, which ink they write in, what they may do. Tools: `read_days`,
`list_lines`, `read_photo`, `add_note`, `set_label`. Writes land in the grant's own event
file; no grant can touch your lines. Revoke the row and the key is gone.

Every read leaves a receipt: a `visit` event in the grant's file saying what was asked for
and how much came back. The phone shows the latest one on the calendar sheet and the whole
log behind it; a line's History says who read it. The Mac window has the same log.

## Building Margin with Margin

Write about the app in the app, like anything else. A Claude Code session in this
repository reads the notebook through the door, labels those lines `margin` (and `bug`
where it is one), fixes what it can, and says what shipped in the chat. Nothing in the
app knows this is happening; it is a reader with a grant.
