# The system

9 November 2026. What dotto is, in six parts and two layers, from everything the notebook
has asked of it since 2 November. This replaces the direction note of 6 November, whose
idea stands: an operating system for a person's life and work, where everything begins
with capture, and the use cases are evidence of what the parts must be, not features.
Three things are fixed, in the README. Everything here is dated.

## What it is

Two layers, with different powers on purpose.

The substrate is a log: one append-only file per originator per device, one writer per
file, every change an event, nothing ever changed in place. The fold is a pure function
from the log to the current state and always gives the same answer on every device, so
files may arrive late or in any order and nothing conflicts. The substrate is not a
computer and must never become one. Its promises come from being simple: total,
replayable, auditable, plain files anyone can read.

The loops are programs. A loop is anything that acts through the door: a Claude session,
an import from Health, a script, one day a program a person asked for in a sentence. It
can do anything a program can, and it reaches the notebook only through the door's tools,
under a key, writing to its own file, leaving a receipt for every read, and the owner takes
back anything it left with one hold. Power lives here, so the fences live here.

In the owner's words: the log is the filesystem, originators are users and processes with
permissions, the door is the system-call interface, loops are daemons with triggers, pages
are the display.

## The six parts

Each has one job. Captures hold. Originators answer for. Shapes mean. Links join. Loops
act. Pages show.

### Captures

What arrives: a line, a photo, a voice note, a walk, a mail, an order, a link from the
laptop. A capture is stamped with who, when and where, and never changes; an edit keeps
the words before. Writing one costs nothing: one gesture, no category, no decision, no
audience. The owner never files.

Today: lines with time, place and history; photos and voice by hash; ways in through the
live line, the camera, the mic, the library, the share sheet, the controls and Siri, and
Health. Missing: video, a drop from the laptop, mail and orders arriving on their own.

### Originators

Whoever a capture, a mark or a loop is by: the owner, a session, the reader, Health, Mail,
a form. An originator has a key, a name once it chooses one, a colour from its id, a page
of its own, and a file of its own. Every read leaves a receipt. The owner takes back
anything an originator left with one hold. A loop runs as an originator.

Today: grants as the owner's events, keys on the Mac, names, colours, devices, pages,
receipts, Logs and History, takeback for notes, links and done. A line by another
originator lands on the owner's page under its own name and goes with one hold, built 9
November; Health is the first such originator, each walk a line in its name. Missing:
takeback for labels on the phone; Mail and the reader bringing lines the same way.

### Shapes

What captures turn out to be: a todo, an event, a person, a book, a plant, a measurement,
a streak, a place. A capture never changes; the shapes read from it live and die. A
capture is often several shapes at once, a quote photo being a quote, a work and a day of
a reading streak, and each has its own lifecycle. Shapes are proposed by originators; the
owner only drops.

A tag is the simplest shape: a name with no fields that lines belong to. Reading, margin,
detox, nursery, a project's code name are all tags, and a label on a line is a link from
the line to its tag.

Two kinds hide under the one word and need different mechanics: a fact on one line, the
yield, the kilometres, done; and a thing many lines share, a book, a person, a fig. See
the design below.

Today, since 10 November: things and facts, as designed; tags still as labels. Missing:
labels folding into things, so a tag has a page like any thing; a kind as more than a
word; streaks, which are a thing with a loop that sets its facts.

### Links

A link joins one thing to another by their ids, and that is all it is. See the design
below. Built 9 November as designed: threads, citations, done as the first fact, the older
shape folded in. Since 10 November a line to a thing is belonging.

### Loops

What runs: a trigger, a capture landing or the clock; an originator it runs as; a budget;
a receipt per run the owner can read. Said once, kept, run, and stopped by the owner.

Today, since 9 November: a loop is the owner's event in the notebook, like a grant: a name,
the grant it runs as, what wakes it, a line landing or the clock at an hour each day, a
brief in the owner's words, a cap on turns and on spend. The Mac, the home, runs each one
and writes a receipt per run into the notebook under the loop's originator, so Logs say it
ran, what it cost and what it said; the owner sets and stops loops in the Mac window, and
the reader is the first loop, carried over from the old switch. Since 10 November the
owner also sets one on the phone, in Setup under Loops, and anyone through the door
proposes one with `propose_loop`: the proposal waits in the inbox and on the Loops page,
and the owner sets it with one tap, under the proposal's own id, or declines it, which is
a stop of that id; the sentence stays the owner's, the shaping is the originator's, and
only the owner's hand makes it run. Still in Swift with no loop record: Health's import,
pushes on words, the projector. Missing: a loop's own originator; a loop reaching outside
with a key; isolation; loops that run programs other than a Claude session.

### Pages

Where shapes and captures are seen: the day page, a line's page, an originator's page,
the inbox, Logs, a tag's lines, a shelf, a plant's page, a yield page. A public page is a
page with an audience. Pages are made from shapes; a page made by dotto for itself is the
milestone.

Today: all pages are code. Missing: a page as a definition over shapes, which is what lets
dotto make the shelf, the plant page and its own site; search over plain words, a small
page of its own.

## Rules found on 9 November

- A capture never changes; shapes live and die.
- A tag is the simplest shape; labelling is linking.
- Finishing is state, not a connection: closes becomes done, a mark on the line finished,
  with the finishing line as evidence.
- Shapes are proposed by originators; the owner only drops.
- Every loop runs as an originator and leaves a receipt.
- One rule for a line by another originator: it lands on the owner's page under its own
  name and goes with one hold.

## Links, the design

From what the notebook has done with links: the plant thread, the reading thread, the
detox and Hamming lines, line to line; a reply citing a quote as plain text; eleven lines
that are one fig, ten that are one book, seven that are one person; and closes, bolted on
to the thread.

**The rule.** A link joins one thing to another by their ids. No types, no words on it.
What it means comes from what its ends are:

- line to line: a thread, the later carrying on from the earlier
- note to line: a citation, the reply pointing at the line it speaks of
- line to shape: belonging, this quote is of that book, this line is under that tag
- shape to shape: nothing in the notebook asks for it, so it is not built

One link per pair, in one direction, from the thing that points to the thing pointed at,
drawn both ways. Anyone with a key may place one; it carries its originator's name; the
owner takes it back with one hold.

**Closes leaves links** and becomes done, the first fact.

**How they show.** On the page a linked line gets one quiet row, like replies: a count and
the first words of the nearest linked line. On the line's page, a plain list of what it is
joined to, by day and first words, grouped: the thread, cited by, belongs to. Inside a
reply a citation is the cited line's first words at its end, tap to go.

**Through the door.** One tool, link, from one id to another. A note added with cites
writes the note and its links together. Existing link events already have the from-to
shape; existing closes fold into done.

**Not done, on purpose.** No words on links, no weights, no graph queries, no link to a
page. Pinning is a mark and belongs to pages. If a word on a link is ever needed, it
arrives as a shape between two things, not as a type.

## Shapes, the design

Decided 9 November, built 10 November. From the notebook: the yield on the harvest line,
the kilometres on a walk, done; eleven lines that are one fig, ten that are one book,
seven one person, four the baby plant; the detox and a reading streak fed over days.

**A thing** is a shape with an id, a name and the originator that made it. Nothing else is
required. Lines belong to it by the link we already have, line to thing, and that is the
belonging; nothing points from a thing, and a note belongs to nothing. Only its own
originator sets it again, to rename it or give it a kind; the newest set stands. A kind is
a word for now, plant, book, person, not a link: nothing in the notebook has asked for a
plant to inherit from a living thing, and a word folds into a link later the way labels
will fold into things.

**A fact** is a key and a value put on a line or a thing by an originator. One per
originator per key; the newest word wins, by the same mark as everything else. Values
are of five kinds, so a page can add yields, draw a streak or put a thing on a map: a
number with a unit, words, a moment, a span, a place. Due, at and span are facts, which
answers the open item on time and place. An unknown key still reads as "key value".

**Done stays its own mark.** It carries evidence, the line that finished it, which no
fact value holds, and a reference kind would duplicate links. It is the first fact in
what it means, not in how it is kept.

**Proposals need no state.** Anything shaped by someone other than the owner stands
unless dropped. The owner drops a thing with one hold, which sets every line loose from
it; takes a fact off, naming whose; takes a line out of a thing. An originator takes back
its own. A drop of a thing is final, and a set arriving late does not bring it back.

**How they show.** On the page a line gets one quiet row: the things it is with and its
facts. On the line's page, "with fig" is a jump to the thing's page, and the facts are a
plain list, each signed, hold to take off. A thing's page: its name, kind and maker, its
facts as its state, the lines that belong to it by day. The inbox gets a row for each
thing made and each fact put on the owner's line or on a thing. The day files say
`_with fig_` and `_yield 10 L · Moss_`.

**Through the door.** `set_thing` makes one, after `list_things`, so the fig is made once;
`link` with a thing as its end is belonging; `set_fact` takes exactly one value. Looking
at the things leaves a receipt like every read.

**Not done, on purpose.** Shape-to-shape links, "same as" for two things that are one,
tags as things, pages as definitions.

## The cases, run through

A quote photo: one capture, linked to the work, on the shelf page, a loop fetching the
book's details. A walk: a capture by Health, a measurement, a line on the day. The
booking mail: a capture by Mail, an event, a loop into the calendar, a row in the inbox.
The harvest: a line with a yield fact, a yield page. The detox: a streak fed by the
owner's lines and, where it can be, by a loop. The oil sale: a page with a way in, orders
arriving as captures under the buyer's name. A bug line: a capture a loop hands to a
session, today a habit. Each case uses every part once and leaves nothing over; that is
the test the parts keep passing.

## Open

- Labels as things, so a tag has a page like any other thing.
- Pages as definitions over shapes.
- Three kinds of written words, the owner's line, an originator's page line and a reply,
  are three event kinds for one act. Not merged; shapes must not deepen the split.
- One originator with two hands, a session and the reader, shares one memory of what it
  has seen.
- A named place: a place fact is coordinates; what calls it the nursery is not built.
- Where loops run and pages are served, the home; media leaving the phone. Both parked,
  and both gate loops and pages.
- The old names: Margin and weeju in code, bundle ids and the conduct note. They stay
  until a deliberate rename.
