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
yield, the kilometres, done; and an entity many lines share, a book, a person, a fig. The
first fact is done, which replaces closes.

Today: tags, as labels. Missing: everything else. The reader's count of 9 November on its
page is the backlog, and the proposed state, with a place for the owner to see a proposal
and drop it, is the first thing shapes need.

### Links

A link joins one thing to another by their ids, and that is all it is. See the design
below. Built 9 November as designed: threads, citations, done as the first fact, the older
shape folded in; a shape as an end waits for shapes.

### Loops

What runs: a trigger, a capture landing or the clock; an originator it runs as; a budget;
a receipt per run the owner can read. Said once, kept, run, and stopped by the owner.

Today, since 9 November: a loop is the owner's event in the notebook, like a grant: a name,
the grant it runs as, what wakes it, a line landing or the clock at an hour each day, a
brief in the owner's words, a cap on turns and on spend. The Mac, the home, runs each one
and writes a receipt per run into the notebook under the loop's originator, so Logs say it
ran, what it cost and what it said; the owner sets and stops loops in the Mac window, and
the reader is the first loop, carried over from the old switch. Still in Swift with no loop
record: Health's import, pushes on words, the projector. Missing: a loop set from the phone
or through the door in a sentence; isolation; loops that run programs other than a Claude
session.

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

- Shapes beyond tags: the fact and the entity, how a proposal is shown and dropped.
- Loops as data: trigger, originator, budget, receipt, stop.
- Pages as definitions over shapes.
- Three kinds of written words, the owner's line, an originator's page line and a reply,
  are three event kinds for one act. Not merged; shapes must not deepen the split.
- One originator with two hands, a session and the reader, shares one memory of what it
  has seen.
- Time and place: a shape needs due, at and span, and a named place; a capture has only
  when and where.
- Where loops run and pages are served, the home; media leaving the phone. Both parked,
  and both gate loops and pages.
- The old names: Margin and weeju in code, bundle ids and the conduct note. They stay
  until a deliberate rename.
