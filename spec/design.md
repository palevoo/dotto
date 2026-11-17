# The design

What Dotto is made of and why: two layers, six parts, and the rules they keep. The three
things that are fixed are in the README. The folder on disk is in `format.md`, the door in
`door.md`, and what is not built in `roadmap.md`.

## Two layers

**The log.** One append-only file per originator per device, one writer per file, every
change an event, nothing changed in place. The reading (the fold) is a pure function from
the log to the current state and gives the same answer on every device, so files may arrive
late or in any order and nothing conflicts. The log is not a computer and must never
become one. Its promises come from being simple: total, replayable, auditable, plain files
anyone can read.

**What acts.** Anything that does something comes through the door: a Claude session, an
import from Health, a loop. It can do whatever a program can, and it reaches the notebook
only through the door's tools, under a key, writing to its own file, leaving a receipt for
every read. You take back anything it left with one hold. Power lives here, so the fences
live here.

Put another way: the log is the filesystem, originators are users and processes with
permissions, the door is the system-call interface, loops are daemons with triggers, and
pages are the display.

## The six parts

Each has one job. Captures hold. Originators answer for. Shapes mean. Links join. Loops
act. Pages show.

**Captures** are what arrives: a line, a photo, a voice note, a walk, a link from the
laptop. A capture is stamped with who, when and where, and never changes; an edit keeps
the words before. Writing one costs nothing, and you never file it. A line's moment is
when it began; one left unsent and come back to begins again then, so it lands on the day
it is sent from.
Ways in today: the live line, the camera, the mic, the library, the share sheet, the
controls and Siri, and Health on the phone; on the Mac a panel that takes words, links and
pictures by typing, paste, drop and Services.

**Originators** are whoever a capture, a mark or a loop is by: you, dotto, Health,
Weather, another person. An originator has a key, a colour from its id, a name once it
chooses one, a page of its own and a file of its own. `door.md` has the rest.

**Shapes** are what captures turn out to be: something to do, an appointment, a person, a
book, a plant, a measurement, a streak. A capture never changes; the shapes read from it
live and die. A capture is often several shapes at once. Shapes are proposed by
originators; you only drop them.

**Links** join one thing to another by their ids, and that is all a link is.

**Loops** are what runs: something that wakes it, an originator it runs as, a budget, and
a receipt per run. Said once, kept, run, and stopped by you. `door.md` has the rest.

**Pages** are where captures and shapes are seen: the day, a line, a thing, a kind, the
inbox, what is to do, what is coming. Today every page is code.

## Rules

- A capture never changes; shapes live and die.
- Where a line was said is part of it and never changes. What it connects to is a link,
  placed afterwards and taken back.
- Shapes are proposed by originators. You only drop.
- Behaviour hangs off a fact, never off a kind. Anything with `due` reminds. Anything done
  is struck through. So a new kind of thing needs no new code to behave.
- A tag's identity is its word. A thing is its id.
- Finishing is a state, not a connection.
- Only your hand makes a loop run. Anyone may propose one.
- Every loop runs as an originator and leaves a receipt.
- A line by another originator lands on your page under its own name and goes with one
  hold.
- The vocabulary grows by addition. A build that meets an event kind, or a value, it does
  not know carries it and passes over it; it never drops the file.
- What comes in lands freely, under its source's name. What goes out goes only on your
  word.
- When the same thing is written a third time it becomes a function with a name. Not
  before.

## Lines

There is one kind of written thing, a line, and where it was said is part of it.

- Said nowhere in particular, it is on its writer's days: yours on the page, an
  originator's on its own page.
- Said on your days by someone else, it is a walk, a booking: something of yours that
  happened.
- Said under a line, it is a reply. A reply may answer a reply; the conversation shows
  flat under its line.
- Said under a thing, it is something said on that thing's page.

Whoever wrote a line changes it. They or you drop it.

## Links

A link joins one thing to another by their ids. No types, no words on it. What it means
comes from what its ends are:

- line to an earlier line: a thread, the later carrying on from the earlier;
- reply to a line: a citation;
- line to a thing: belonging.

One link per pair, in one direction, drawn both ways. Anyone with a key may place one, it
carries its originator's name, and you take it back with one hold.

Not done, on purpose: words or weights on links, graph queries, links between two things.

## Shapes

**A thing** is a shape with an id, a name and the originator that made it: a fig, a book,
a person. Lines belong to it by a link. Only its maker renames it or gives it a kind, a
word such as plant or book.

**A fact** is a key and a value put on a line or a thing by an originator: `distance
7.3 km` on a line about a walk, `state potted` on the fig. One per originator per key; the
newest stands. A value is a number with a unit, words, a moment, a span or a place.

**Done is its own mark.** It carries the line that finished it, which no fact value
holds.

**A tag is the simplest thing**: a lower-case word that lines are under. Nobody makes it.
Its id comes from its word, so every originator on every device lands on the same tag
with no lookup, and it is there as long as a line is under it. It has a page and takes
facts like any thing.

**A kind has a shape**: what a paper, a plant, a person has, in order, and what each is.
Whoever makes a thing of a kind is told what the kind has and fills it, so the things of
a kind are alike and their pages read alike. The newest word for a kind stands; kinds most
notebooks come to have a usual shape until someone says otherwise.

**Proposals need no state.** Anything shaped by someone other than you stands unless you
drop it. Dropping a thing sets every line loose from it and is final.

Some fact keys mean something to the apps:

- `todo` on a line: something to do. Done closes it; nothing else needs taking off.
- `at`: when something happens whether or not you do anything, an appointment, a class.
  It is never to do, and it passes by itself.
- `due`: when something wants you, a todo to be done by then or a plain reminder.
- `since` on a thing makes it a streak. Its run is worked out from the notebook each time
  it is shown, never set. It runs one of two ways. Without: every day counts unless a line
  that is with it carries `break`. With (`counts` is "with"): a day counts when a line is
  with it, a walk, a page read. `span` is how long it is meant to run, `ended` stops it,
  and a newer `since` begins it again.

Not done, on purpose: a shape made of other shapes; "same as" for two things that are one.

## The home

The home is where the notebook is kept whole and where what acts runs: the folder, the
door, the keys, the pushes, the loops. The apps are for writing and looking. Today the
home is inside the Mac app. What it does lives in Core wherever it can, so it can be
tested without a screen and one day run by itself on a machine that stays on.

**One reading.** An originator reads what lands once, with every sentence woken by a line
kept in mind and the whole notebook in view. The reading is handed what it needs as it
starts: what is new to its hand, the days those lines are on, and the beginning of
anything newly kept beside one. It touches nothing outside.

**What a line points at is opened and kept beside it**, by the home, so that whoever
reads never has to reach outside. `door.md` says exactly what is opened and what is not.
With the page kept, the reading can make a thing of it, a paper, a talk, a book, with what
is worth knowing as its facts.

**In freely, out on your word.** What comes in lands as a capture under its source's
name. What goes out goes only on your word: a line you wrote, a tap, or a standing
allowance. So nothing that reads a stranger's page ever holds a way out.

## The weather of a line

The weather follows from when and where, and a line already has both. So nothing new is
captured and writing costs what it did. It is found out afterwards and said once per line.

- It is not a mark someone put on the line. It is an event of its own,
  `conditions.set`, one per line. It makes no inbox row and wakes no reading. You take it
  off a line with one hold.
- What is said: at the line's hour, the temperature, the sky, the wind, the humidity, the
  rain; and over the 24 hours before it, how much fell, the coldest and the warmest.
- It is the weather model's value for that square of land, not a measurement on it. The
  page says so.
- The source is Weather, an originator with no page. Its values come from Open-Meteo,
  whose data may be kept and passed on (CC BY 4.0, credited where the weather is shown).
  Apple's weather cannot be used: its licence forbids keeping the data.
- The phone asks, so nothing waits on a Mac being awake. What is sent is the place
  rounded to a hundredth of a degree, about a kilometre, and a span of days. Because that
  goes to someone outside, it is off until switched on in Setup.

## What the pages show

**The day page.** Your lines by time, the live line at the foot. Under a line, one quiet
row each for its replies (the latest reply's words, with a count), for what it is linked
to, and for the things it is with and its facts.

**A line's page.** The line, where and when it was written with the weather there, what it
is in one block, its thread, the replies as a conversation with the place to reply pinned
at the foot, and its History: who read it and what was done to it. Hold a reply of yours
to change or delete it. Hold a fact, a tag or "with fig" to take it off.

**Something to do** wears one mark wherever the line is drawn: a ring under its time while
it is open, filled once it is done. Tap it and the line is finished where it stands; tap
again and it is open. You say a line is to do, or is not, in its hold menu.

**Todos.** The same lines with the same mark, due first. A line finished today keeps its
place until the day ends. A todo with no moment that has waited three weeks steps back
into Someday; it is never late.

**What is coming.** Everything with `at` or `due`, by day, with a ring under its day in
the calendar. The phone says it by itself, with no Mac and no network: an event the
evening before and an hour before, something due at its moment, with Done and In an hour
on a notice about a todo. The notices are worked out from the notebook each time it is
read, so a moment moved, taken off or finished needs nothing undone.

**The inbox.** What others left that may want you: replies, lines on their pages, tags,
links, things, facts, names, proposed loops. One flow, newest first, and what asks and has
no answer yet is in black. Each row is answered where it is: reply under it, set or
decline a loop, drop a mark. Opening a line is what reads it, on every device. Nothing is
stored for the inbox; it is a reading of the same files.

**A thing's page.** Its name, kind and maker; its shape's facts in its shape's order, a
few sentences as a paragraph, an address as a link, the rest as rows; then the lines that
belong to it by day. Hold the name to drop it. **A kind's page** lists its things with
their short facts. **A tag's page** is a thing's page headed by its word.

**A streak's page.** The run in days, a few quiet words, and every day since it began as a
dot, seven to a row: filled for a day that counts, an empty ring for one that broke, today
in the one colour. A dot with a line behind it leads to that line. It never counts at you
and never asks to be kept.

**Search.** Plain words: every word typed must appear, case and accents aside, and a word
is found inside a longer one. A line is found through its own words, a reply under it, a
thing it is with or a tag it is under. Things whose names match come first.

**An originator's page.** The lines it wrote for itself. You reply under them as under
your own.

**Read, and nothing said.** A line of yours from today that was read and had nothing said
under it wears a small dot under its time, in the colour of whoever read it. That tells
it apart from a line nobody has got to yet.

**Logs** show every read and every run. **Setup** is a list of steps, one for each thing
you can turn on.

Everyone has a colour and a dot of their own, from their id. The dot is drawn by hand, no
two alike, and it is their mark everywhere before they choose a name and after. The apps
have one colour of their own, persimmon, and only dotto wears it, on the dot the app icon
shows. `design/` says how a dot is drawn.
