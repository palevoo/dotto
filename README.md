# dotto

You write things down. Something reads them and helps.

Three things are fixed:

1. Writing costs nothing. One gesture, no categories, no decisions, no audience.
2. Your words are yours. Only you write them. Anyone else writes beside them, or on a
   page of their own, and can be removed.
3. Meaning comes later. What a line is, what it connects to, what it should trigger, is
   decided after it is written, and only once it has earned it.

Everything below is where we are now, not what dotto is. It changes as we use it. The six
parts, the two layers and the links design are in `spec/system.md`. The apps are called dotto;
the targets, schemes and bundle ids still say Margin until a deliberate rename.

## Now (November 2026)

An iPhone app with one page: days scrolling up into the past, a live line at the bottom
with the time, a camera and a mic. A Mac app that holds the grants and opens the door.
A folder of plain files that both write into. The one other author so far is a Claude Code
session with a grant; it has no name until it chooses one.

    spec/architecture.md    §0 is what is built; the rest is a sketch
    spec/conduct.md         how whoever comes through the door behaves
    spec/system.md          what dotto is: six parts, two layers, the links design; dated 9 November
    Core/                   Swift package: events, fold, file store, projector, the door, CLI, tests
    App/project.yml         both apps, generated with XcodeGen into App/Margin.xcodeproj
    App/iOS/                iPhone app; Shared/ is compiled into the controls too, Common/ into the share sheet too
    App/Controls/           Write and Photo controls: Action button, Control Center, lock screen
    App/Share/              the share sheet; keeps lines in the app group until the app takes them
    App/Mac/                Mac app: the home's window, and the live line from anywhere
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
The icon: `swift App/Design/icon.swift App/iOS/Sources/Assets.xcassets/AppIcon.appiconset`, two dots on a sheet,
dotto's eyes. The palette and type of 9 November are in `App/iOS/Common/Theme.swift`, `App/Mac/Sources/MacTheme.swift`
and the top of `site/index.html`: a cool near-white ground, black ink, nothing coloured but the dot.

## Ways in

On the phone: the live line, the camera, the mic, the library, the share sheet, the controls
and Siri, and Health. A photo taken with dotto's camera is kept in Photos too once you say so
in Setup, "Keep photos in Photos": the camera's own bytes at full size, with their moment and
place. It is asked for as add-only, so dotto puts photos in and reads nothing through it.

On the Mac the live line is a small panel over whatever you are in: `⌥⇧Space`, or a click on
the two dots in the menu bar. It takes the keys without taking the app you were in away from
you. Return keeps the line, as yours, from this Mac; Esc puts it away with the words waiting;
a click elsewhere puts an empty line away and leaves a begun one where it is. Paste words, a
link or a picture into it; drag a picture, a screenshot's floating thumbnail, a link or words
onto the dots or onto the line; or select words in any app and choose Services · Keep in
dotto. A link lands as its address; a picture is kept as the phone keeps one. Other files are
named as left out, for now. The clipboard is read when you paste and a drop when you drop
it; nothing is watched, and none of it needs a permission. The dots are persimmon while the
door is open. What a paste or a drop becomes is decided in Core (`Arrival.swift`), under test.

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
a new key for the same author. Tools: `whats_new`, `read_days`, `list_lines`, `search`,
`read_photo`, `add_note`, `set_label`, `link`, `mark_done`, `set_thing`, `list_things`,
`set_fact`, `propose_loop`, `list_loops`, `write_line`, `add_line`, `edit_line`,
`delete_line`, `choose_name`. Writes
land in the grant's own event file; no grant can touch
your lines, and a grant changes or deletes only lines it wrote. Revoke the grant and the key
stops opening the door; the author's events stay. A request may add a `Dotto-Device`
header to say which hand of the same grant it is, as the reader does; the stamp shows in
Logs and in a line's History.

`whats_new` is the inbox: what happened since the grant last looked, replies first, then
new lines, lines changed, marks taken back, names chosen. Each look is a receipt that
records how long every event file was, so the next look starts after that count per file
and a line that reaches the Mac late through iCloud is still caught.

You have the same inbox, with a screen. What others leave that may want you, replies under
your lines and in conversations you are in, lines on their pages, labels, links, names,
gathers newest first, reached from the calendar sheet or from the count beside the date.
It is one flow, newest first, and what asks and has no answer yet is in ink. Each row is the
thing itself and is answered where it is: Reply opens a field under a reply or a line, Set it
and Not now answer a proposed loop, a mark is dropped with one tap; the line or thing it is
about is the row's last line, a jump. Opening the line is what reads it: a `visit` in your own file names the
line, so the same rows are read on every device. What is about no one line, labels folded
together, a name, is read by opening the inbox, whose `visit` records how long every event
file was, so a mark that reaches a device late is still new. The Mac shows the same list;
the looks are made on the phone. Nothing is stored for the inbox: it is a fold of the same
files.

A grant is an author with a fresh id and no name. It may write lines of its own, which make
up its page, reached from the calendar sheet; you reply under them as under your own, and it
reads your replies with `mine=true`. It chooses what it is called when it wants to, and the
name stands beside everything it does from then on. Until then it is only a mark.

Something that is yours and happened, a book you asked for, a booking, a walk, another
originator puts onto your page under its own name with `add_line`, on the day it happened; it
wears that name on the page, and you drop it with one hold. Health is such an originator:
each walk is a line in Health's name on your day.

A link joins one thing to another by their ids, and that is all it is. A later line to an
earlier one it carries on from is a thread: the same plant, book or errand, written days
apart. A note to a line it speaks of is a citation, and the page makes it a jump. Finishing
is not a link but a state: `mark_done` says a line is finished, by which later line when one
did, and the line is struck through. On the page a linked line gets one quiet row, like
replies; a line's own page lists its thread, done, and the notes that cite it. Hold a row
there to take it back, or join the line to an earlier one of yours with "Carries on from…".

Shapes are what lines turn out to be, and they are proposed, never filed by you. A thing is
a shape with a name that lines belong to: a fig, a book, a person, the detox. An originator
makes it once with `set_thing`, after `list_things`, and puts each line with it through
`link`; it may give it a kind, a word like plant or book. A fact is a key and a value on a
line or a thing, `set_fact`: yield 10 L on the harvest line, state potted on the fig; one
per originator per key, the newest wins; a value is a number with a unit, words, a moment,
a span or a place. On the page a line gets one quiet row with the things it is with and its
facts; on its own page "with fig" is a jump to the thing's page, which has its facts as its
state and the lines that belong to it by day. Everything shaped stands until you drop it:
hold a fact to take it off, hold a thing's name to drop it, hold "with fig" to take the line
out. The inbox shows each thing made and each fact put on your lines.

A tag is the simplest thing: a lower-case word that lines are under, `set_label`. Nobody
makes it; its id comes from the word, so the reader's #reading and a loop's #reading are one
tag on every device with no lookup, and it stands as long as a line is under it. A label is
the link from the line to it, signed by whoever filed it. It has a page like any thing,
headed by its word, reached from the chips on the calendar sheet or from the tag on a line's
page, and it takes facts like any thing, which is how a tag becomes a streak. Hold a tag on a
line to take it off; hold the word on its page to take every line out from under it. The
word is never retired: a label after that stands.

Replies under a line show on the page as one quiet line, the latest reply's words with a
count before it. The line's page holds the conversation, with the place to reply pinned at
the foot; hold a reply of yours to change or delete it. Everyone has a colour of their own,
from their id, which is their mark everywhere until they choose a name and after.

Search is plain words over the notebook, the same on the phone, through the door and in the
CLI: every word typed must appear, case and accents aside, and a word is found inside a
longer one so a Russian ending does not hide it. A line is found through its own words, a
reply under it, a thing it is with or a tag it is under, and the reply that held the word is
shown with it; things whose names match come first. On the phone it is one page, reached from
the calendar sheet beside Inbox, that finds as you type. Through the door it is `search`, and
its receipt says what was searched for, so a line's History knows it was found that way.

Every read leaves a receipt: a `visit` event in the grant's file saying what was asked for
and how much came back. The phone shows the latest one on the calendar sheet and the whole
log behind it, called Logs; a line's History says who read it. The Mac window has the same log.

A note written through the door reaches the phone as a push. The phone writes its push
address into the folder as `devices/<device>.json` once notifications are allowed in
Setup; the Mac, holding the developer account's push key in its keychain, hands the note
to Apple. Marks stay silent when they land: labels, links, things and facts are for the page,
not the pocket. One fact speaks once, later: a line with a `due` moment, not yet done, reaches
you as a push when the moment comes, sent by the Mac from the fold, so a moment moved or
taken off never fires and nothing fires twice.

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

When a loop wakes it runs one headless session of the `claude` command you already pay for:
the door as its only server, every built-in tool off, no settings and no project in reach,
the door's conduct and the loop's brief as its whole brief, the loop's caps, nothing kept
afterwards. Then it waits again. A run is started for what was waiting; if it ends with the same things
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

## Building dotto with dotto

Write about the app in the app, like anything else. A Claude Code session in this
repository reads the notebook through the door, labels those lines `margin` (and `bug`
where it is one), fixes what it can, and says what shipped in the chat. What was decided,
floated or found missing along the way goes on its own page. Nothing in the app knows
this is happening; it is an author with a grant.
