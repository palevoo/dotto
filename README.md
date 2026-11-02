# Margin

A notebook that is yours first. One page, days scrolling up into the past, the time in the
margin the moment you start a line. Everything lives in a folder of plain files you own.
Readers, weeju among them, are grants added later and write in their own ink, in the margin.

    spec/architecture.md    the stance and the plan; §0 is what is being built now
    Core/                   Swift package: events, fold, file store, projector, the door, CLI, tests
    App/project.yml         both apps, generated with XcodeGen into App/Margin.xcodeproj
    App/iOS/                iPhone app: the page
    App/Mac/                Mac app: the grant holder, sandboxed, opens the door on localhost
    App/Design/icon.swift   draws the app icon into the asset catalog
    mock/                   the web prototype the app is modelled on

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
command in the Core package is that door from a terminal:

    cd Core && swift build --product notebook
    .build/debug/notebook list <folder>                       every line with its id
    .build/debug/notebook list <folder> --label margin        the lines filed under a label
    .build/debug/notebook label <folder> <entry-id> margin    file a line (as weeju)
    .build/debug/notebook note <folder> <entry-id> "shipped"  a line under yours (as weeju)
    .build/debug/notebook show <folder>                       the fold, as day pages

## The door

The Mac app is sandboxed: it sees exactly the folder you pick and nothing else. It serves
the Model Context Protocol on `127.0.0.1:27830/mcp`, behind a key per grant. A grant is a
row in its window: who, which ink they write in, what they may do. Tools: `read_days`,
`list_lines`, `add_note`, `set_label`. Writes land in the grant's own event file; no grant
can touch your lines. Revoke the row and the key is gone.

## The loop that builds Margin with Margin

Write about the app in the app, like anything else. A Claude Code session in this
repository reaches the notebook through the door, files those lines under `margin` (and
`bug` where it is one), fixes what it can, and leaves a note under each line when it
ships. Nothing in the app knows this is happening; it is a reader with a grant.
