# Dotto

You write things down. Something reads them and helps.

Dotto is a notebook with one page. You write a line, take a photo or say something, and it
is kept on the day you wrote it, in a folder of plain files that is yours. Nothing is sorted
while you write. Afterwards whoever you let in reads what you wrote and helps: answers what
asks, marks what is to do and tells you when it is due, gathers the lines about one thing, a
plant, a book, a person, into a page of its own, keeps a streak without being told. Today
the one who reads is a Claude Code session of your own, through a small server on your Mac.

Three things are fixed:

1. Writing costs nothing. One gesture, no categories, no decisions, no audience.
2. Your words are yours. Only you write them. Anyone else writes beside them, or on a
   page of their own, and can be removed.
3. Meaning comes later. What a line is, what it connects to, what it should trigger, is
   decided after it is written, and only once it has earned it.

Everything below is where it is now, November 2026, not what Dotto is. It changes as it is
used.

## What is here

    App/iOS/                the iPhone app: one page of days, a live line at its foot, a camera and a mic
    App/Controls/           Write and Photo controls: Action button, Control Center, lock screen
    App/Share/              the share sheet; keeps lines in the app group until the app takes them
    App/Mac/                the Mac app, the home: it opens the door, holds the keys, runs the loops
    Core/                   the Swift package both stand on: events, the fold, the files, the door, a CLI, the tests
    App/project.yml         both apps, generated with XcodeGen into App/Dotto.xcodeproj
    App/Config/             who signs and the prefix every id is made from; your own in Signing.xcconfig
    App/Design/icon.swift   draws the app icons into the asset catalogs
    spec/format.md          the notebook folder as a format: every kind of event and whose word counts
    spec/sample/            two invented days as such a folder, with the pages Core reads from them
    spec/door.md            what comes through the door, what it may do, and how the pages show it
    spec/architecture.md    §0 is what is built; the rest is a sketch
    spec/conduct.md         how whoever comes through the door behaves
    spec/system.md          the design: six parts, two layers, links; dated 9 November
    site/                   dotto.works

It is early. One person has used it every day since 2 November 2026, and it is built from
what they wrote in it. The iPhone app is in TestFlight by invitation. There is no Mac
download yet, so the home is built from source. MIT licence. Write to hi@dotto.works.

## Build

Xcode 16 or later, on macOS 14 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The phone app is for iOS 18. A loop is run with the `claude` command, Claude Code, signed in
as you; without it everything else works and nothing answers.

    cd Core && swift test                      # the fold and the projector, under test
    cd App && xcodegen generate                # writes Dotto.xcodeproj; do not edit it by hand
    open App/Dotto.xcodeproj                   # pick your phone, run
    xcodebuild test -project App/Dotto.xcodeproj -scheme Dotto -destination 'id=<booted simulator>'
                                               # the live line driven as a thumb would, in App/UITests

For a simulator and for dotto dev nothing more is needed. To run on a phone, or to sign the
Mac app, copy `App/Config/Signing.example.xcconfig` to `Signing.xcconfig` beside it and write
your own team and id prefix there; git ignores that file. The ids are `<prefix>.app` for the
phone, with `.share` and `.controls`, the group `group.<prefix>`, and `<prefix>.mac`.

Every UI test launches the phone app on a notebook of its own, new and empty, under the
simulator's temporary directory (`-uitest-notebook <name>`, debug builds only; see
`App/UITests/Launch.swift`), so no test meets what another wrote and the day they run on does
not matter. `-uitest-seed-photos` adds the lines the tests read; `-uitest-seed-yesterday <n>`
adds n lines on the day before.

dotto dev is the Mac app under another identity, for trying a change without touching the
home or its notebook: its own bundle id, settings and keychain entries, the door on 27831,
`⌃⌥⇧Space`, plum dots in the menu bar, and no loops ever (`App/Mac/Sources/Identity.swift`).

    xcodebuild build -project App/Dotto.xcodeproj -scheme DottoMacDev -derivedDataPath App/build/dev
    open -n "App/build/dev/Build/Products/Debug/dotto dev.app" --args -dotto-folder /tmp/some-notebook

The Xcode project file is generated. Change `App/project.yml`, or a script under
`App/Scripts`, which the project carries a copy of, then regenerate.
Every build says the commit it was made from (`App/Scripts/stamp.sh`): the phone shows it
at the foot of Setup with when that commit was made, the Mac in its window header, and the
door says it on arrival. A `+` after the commit means uncommitted changes were in the tree.
The script writes a small header before the build and Xcode reads it as it makes each
Info.plist, so the app is signed with the stamp in it and nothing is written into it
afterwards. The build number comes the same way, the moment of that commit to the minute,
so the app and what is embedded in it carry one number and a later commit a higher one; an
archive, which is what is sent out, is not made from a tree with uncommitted changes. Hold it
against `git log` to know whether what is running is what the repository has.
The icon: `swift App/Design/icon.swift App/iOS/Sources/Assets.xcassets/AppIcon.appiconset`, two dots on a sheet,
Dotto's eyes. The Mac's is the same sheet as a rounded square, drawn at each size the Mac asks for:
`swift App/Design/icon.swift --mac App/Mac/Assets.xcassets/AppIcon.appiconset`, and with `--dev` into
`AppIconDev.appiconset` for dotto dev, whose eyes are plum. The palette and type of 9 November are in `App/iOS/Common/Theme.swift`, `App/Mac/Sources/MacTheme.swift`
and the top of `site/index.html`: a cool near-white ground, black ink, nothing coloured but the dot.

## Ways in

On the phone: the live line, the camera, the mic, the library, the share sheet, the controls
and Siri, and Health. A photo taken with Dotto's camera is kept in Photos too once you say so
in Setup, "Keep photos in Photos": the camera's own bytes at full size, with their moment and
place. It is asked for as add-only, so Dotto puts photos in and reads nothing through it.

On the Mac the live line is a small panel over whatever you are in: `⌥⇧Space`, or a click on
the dot in the menu bar. It takes the keys without taking the app you were in away from
you. Return keeps the line, as yours, from this Mac; Esc puts it away with the words waiting;
a click elsewhere puts an empty line away and leaves a begun one where it is. Paste words, a
link or a picture into it; drag a picture, a screenshot's floating thumbnail, a link or words
onto the dot or onto the line; or select words in any app and choose Services · Keep in
Dotto. A link lands as its address; a picture is kept as the phone keeps one. Other files are
named as left out, for now. The clipboard is read when you paste and a drop when you drop
it; nothing is watched, and none of it needs a permission. The mark in the menu bar is one dot: the menu bar's own colour at rest,
persimmon only while Dotto is working, hollow when the door is closed. What a paste or a drop becomes is decided in Core (`Arrival.swift`), under test.

A line of yours with a link in it points at something. The Mac opens exactly that address
and keeps its words beside the line, like a photo: a web page or a PDF, with its title and
where it came from. Only links in your own lines, only addresses out on the web, nothing of
yours sent. Whoever reads the line then reads what it pointed at, through `read_kept`, and
nobody who reads has to reach outside. The row on the phone says `kept:` and its title.

## The folder

    <notebook>/
      notebook.json                   id, created, owner
      events/<author>.<device>.jsonl  one writer per file, append-only, one event per line
      media/<hash>.<ext>              photos and voice by content hash
      days/YYYY-MM-DD.md              derived pages, regenerated after every change

A line in an event file that cannot be read, a write cut short, damage on the way, is passed
over and named, by file and line number in the Mac's window and as a count in the phone's
Setup; it never costs the rest of its file or the notebook, and the next write starts on a
line of its own.

Anyone with the folder can take part by appending to a file of their own. The `notebook`
command in the Core package does that from a terminal:

    cd Core && swift build --product notebook
    .build/debug/notebook list <folder>                       every line with its id
    .build/debug/notebook list <folder> --label margin        the lines under a label
    .build/debug/notebook add <folder> "words" --author <id>  a line on that author's page
    .build/debug/notebook label <folder> <entry-id> margin --author <id>
    .build/debug/notebook note <folder> <entry-id> "shipped" --author <id>
    .build/debug/notebook link <folder> <from-id> <to-id> --author <id>
                                                              a later line to the earlier one it carries on from, or a note to a line
    .build/debug/notebook done <folder> <entry-id> [--by <id>] --author <id>   the line is finished
    .build/debug/notebook name <folder> Moss --author <id>    what that author is called from now on
    .build/debug/notebook search <folder> olive oil           the lines in which every word appears, newest first
    .build/debug/notebook show <folder>                       the fold, as day pages

Anything written by someone other than the owner names its author; there is no default.

## The door

The Mac app reads the folder you pick and nothing else, and serves the Model Context
Protocol on `127.0.0.1:27830/mcp`, behind a key per grant. A grant is one key for an author,
and it is your event in the notebook: it says who the key is for and what it may write, and
carries the key's hash, never the key. The Mac window shows the command that connects a
Claude Code session with that key. Whoever comes through reads the notebook, leaves notes
under lines, files lines under tags, joins a line to an earlier one, gathers lines into
things and puts facts on them, proposes loops, and keeps a page of its own. It cannot touch
your lines, and everything it does stands until you drop it with one hold. Every read leaves
a receipt you can see.

All of it, tool by tool, and how the phone shows each part, is in `spec/door.md`.

## Loops

A loop is a sentence said once, kept, run, with a receipt each time. It is your event in the
notebook, like a grant: `loop.set` names it, says which grant it runs as, what wakes it, a
line landing or the clock at an hour every day, a brief in your words, and a cap on turns
and on spend; `loop.stop` ends it. Every device holding the folder knows the same loops; the
Mac, the home, runs them (`App/Mac/Sources/Reader.swift`). Set one in the Mac window under
one of the grants: it uses that grant's key and author, so it is the same being as a session
started by hand, and it sends the header `Dotto-Device: reader` so Logs say which hand. The
reader is the first loop, woken by lines; a Mac that had the reader switched on writes that
loop once and sets the switch aside. The phone sets one too, in Setup under Loops, with the
same fields. Anyone through the door proposes one with `propose_loop`, `loop.propose` in
the notebook, when you have said in a line that you want something kept happening: the
proposal waits in your inbox and on the Loops page, on the phone and the Mac, and you set it
with one tap, as the proposer's grant under the proposal's own id, or decline it, which is a
stop of that id. Only your hand makes a loop run. `list_loops` says which run and which wait.

What an originator learns from being corrected it keeps: a plain line on its own page under
`learned`. Every hand of it is told those lines when it arrives, so a correction made once
holds for every reading after; it changes or deletes them as it learns, and you drop one with
a hold.

The loops woken by a line are not run one by one. Each is a sentence kept in mind, and an
originator reads what lands once, with all of them and the whole notebook in view: one
session where two read the same line with half the picture each. A loop on the clock runs by
itself.

When a loop wakes it runs one headless session of the `claude` command you already pay for:
the door as its only server, every built-in tool off, no settings and no project in reach,
the door's conduct and the loop's brief as its whole brief, the loop's caps on turns and
spend and a quarter of an hour on time, nothing kept afterwards. A loop stopped, or the app
quitting, ends a session under way. A proposal shows the caps it asks for before you set it. Then it waits again. A run is started for what was waiting; if it ends with the same things
still waiting, offline, logged out, refused, it is not started for them again, and runs when
something new lands or with Look Now. When the run ends, a receipt, `loop.ran`, goes into the
notebook under the loop's own originator: when, how it went, turns, cost, what it said at
the end. Logs show it on every device. Nothing is registered with the system; if you want
loops after a reboot, set the app to open at login like any app, and keep the Mac awake.

Each run is also written down step by step as it happens: `reader-runs/` holds a record per
run, every door tool it called with what it sent, what came back, what it said, and the
cost, with the raw stream beside it; `reader.log` is the plain trail. The window shows each
loop's live state, what woke it, when a clock loop fires next, and its last runs with their
steps; Look Now runs a loop without waiting.

## Building Dotto with Dotto

Write about the app in the app, like anything else. A Claude Code session in this
repository reads the notebook through the door, labels those lines `margin` (and `bug`
where it is one), fixes what it can, and says what shipped in the chat. What was decided,
floated or found missing along the way goes on its own page. Nothing in the app knows
this is happening; it is an author with a grant.
