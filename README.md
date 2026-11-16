# Dotto

Capture anything. Dotto takes it from there.

Dotto is a notebook with one page. You write a line, take a photo or say something, and it
is kept on the day you wrote it, in a folder of plain files that is yours. Nothing is sorted
while you write. Afterwards Dotto reads what you wrote and takes it from there: it notices
which lines are one thing, a plant, a book, a person, and gives that thing a page; it says
what a line is, something to do, an appointment, a question, and answers, reminds or counts
accordingly; and it does what you asked it to keep doing.

Three things are fixed:

1. Writing costs nothing. One gesture, no categories, no decisions, no audience.
2. Your words are yours. Only you write them. Anyone else writes beside them, or on a
   page of their own, and can be removed.
3. Meaning comes later. What a line is, what it connects to, what it should trigger, is
   decided after it is written, and only once it has earned it.

## How it fits together

- **The phone app** is where you write and look: one page of days with a live line at its
  foot, a camera and a mic, the share sheet, controls and Siri.
- **The folder** is the notebook: plain files, one writer per file, nothing changed in
  place. Any program can read it. `spec/format.md` is the format.
- **The Mac app** is the home. It holds the folder, opens the door, keeps the keys and
  runs the loops. It is also a way in: a small panel for a line, a link or a picture.
- **The door** is a local server (Model Context Protocol) on the Mac. Whoever reads the
  notebook comes through it with a key, reads, and writes beside your lines, never over
  them. Today that is a Claude Code session of your own. `spec/door.md`.
- **A loop** is a sentence you said once that the home keeps and runs: when a line lands,
  or at an hour every day.

The design, in six parts, is in `spec/design.md`. What is not built is in
`spec/roadmap.md`.

## State

Early. One person has used it every day since November 2026, and it is built from what
they wrote in it. Nothing is released yet: both apps are built from source. MIT licence.
Write to hi@dotto.works.

## What is here

    App/iOS/         the iPhone app
    App/Share/       its share sheet
    App/Controls/    its controls: Action button, Control Center, lock screen
    App/Mac/         the Mac app: the home, and dotto dev
    App/UITests/     the phone app driven as a thumb would
    App/project.yml  both apps, made into App/Dotto.xcodeproj by XcodeGen
    App/Config/      the version, and who signs
    App/Scripts/     stamp.sh writes the commit into every build
    Core/            the Swift package both apps stand on, with its tests
    design/          the look: the dot, the colours, and the program that draws the icons
    spec/            the format with a sample notebook, the door, the design, the roadmap
    site/            dotto.works

## Build

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The phone
app runs on iOS 18 and later, the Mac app on macOS 14 and later.

    (cd Core && swift test)             # the package's tests
    (cd App && xcodegen generate)       # writes App/Dotto.xcodeproj; never edit it by hand
    open App/Dotto.xcodeproj

Three schemes: `Dotto` is the phone app, `DottoMac` the home, `DottoMacDev` dotto dev.

For a simulator and for dotto dev nothing more is needed. To run on a phone, or to sign
the home, copy `App/Config/Signing.example.xcconfig` to `Signing.xcconfig` beside it and
write your own team and id prefix there; git ignores that file. The phone app uses push
notifications, which need a paid developer account.

**dotto dev** is the Mac app under another identity, for trying a change without touching
the home or its notebook: its own settings and keys, its own port, and no loops.

    xcodebuild build -project App/Dotto.xcodeproj -scheme DottoMacDev -derivedDataPath App/build/dev
    open -n "App/build/dev/Build/Products/Debug/dotto dev.app" --args -dotto-folder /tmp/some-notebook

**The UI tests** run the phone app in a simulator, each on an empty notebook of its own:

    xcodebuild test -project App/Dotto.xcodeproj -scheme Dotto -destination 'platform=iOS Simulator,name=<an iPhone>'

**Loops** are run with the `claude` command, Claude Code, signed in as you. Without it
everything else works and nothing answers.

Every build says which commit it was made from: the phone at the foot of Setup, the Mac
in its window header, the door when a session arrives. A `+` after it means the tree had
uncommitted changes.
