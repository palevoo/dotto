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
Health. Since 10 November the laptop is a way in: the live line as a panel on the Mac, by a
hotkey or the dots in the menu bar, taking words, links and pictures by paste, by drop and
through Services; and a photo taken on the phone is kept in Photos too when the owner says
so. Since the same day a link in the owner's line is opened by the home and what it
points at is kept beside the line. Missing: video, a video's transcript, files other than
pictures from the laptop, the share menu on the Mac, mail and orders arriving on their own.

### Originators

Whoever a capture, a mark or a loop is by: the owner, a session, the reader, Health, Mail,
a form. An originator has a key, a name once it chooses one, a colour from its id, a page
of its own, and a file of its own. Every read leaves a receipt. The owner takes back
anything an originator left with one hold. A loop runs as an originator.

Since 10 November every notebook has one originator of its own, dotto, and an originator
acts through hands; see the design below.

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
the line to its tag. Since 10 November that sentence is literally how it is kept.

Two kinds hide under the one word and need different mechanics: a fact on one line, the
yield, the kilometres, done; and a thing many lines share, a book, a person, a fig. See
the design below.

Today, since 10 November: things and facts, as designed, and tags as things, each with a
page. Missing: a kind as more than a word; streaks, which are a tag or a thing with a loop
that sets its facts; "same as" for two things that are one.

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

Today: all pages are code. Since 10 November two pages stand over shapes, reached from the
calendar sheet: Todos, the lines anyone marked todo and nobody marked done, due first; and
a page per kind of thing, the books, the plants, the people, each thing with its facts and
its lines. A tag's page is a thing's page. The line's page shows what a line is in one
block, and the inbox is one flow answered in place. Search is a small page of its own
since 10 November: plain words, every one found, through a line's words, a reply, a thing
or a tag; the same search is the door's `search`, with a receipt. Missing: a page as a
definition over shapes, which is what lets dotto make the shelf, the plant page and its
own site.

## Rules found on 10 November

- The vocabulary grows by addition, so an older build carries an event kind it does not
  know, counts it and passes over it; it never drops the file. Found when shapes added four
  kinds and a phone and a Mac could be on different builds.
- Only the owner's hand makes a loop run. Anyone may shape one as a proposal; the owner
  sets it with one tap or declines it.
- A tag's identity is its word. A thing is its id, and two originators making "the fig"
  make two figs; a tag must converge with no lookup, so its id is made from the word, and
  nobody owns it. Found when asking whether things were designed well enough to be tags.
- The vocabulary grows by addition one level down too: a kind of read an older build does
  not know is carried by its word, not refused. Found when search needed a new kind of
  receipt and a known event kind with an unknown word inside would have cost the file.

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

**A tag is a thing**, since 10 November, with one rule of its own: its id comes from its
lower-cased word, so every originator on every device lands on the same tag with no lookup,
and nobody made it. It is there while a line is under it. A label is the link from the line
to it; the label events already in the files fold into that link, so nothing migrates. The
owner takes one label off as any link, and drops the tag whole, which takes every line out
from under it and retires nothing: a label after the drop stands. A tag takes facts like
any thing; that is how the detox becomes a streak without becoming something else. A tag
is not set, has no kind, and is not counted among the kinds; it has a page like any thing.

**Not done, on purpose.** Shape-to-shape links, "same as" for two things that are one,
pages as definitions.

## The home, the design

Decided 10 November; built a piece at a time, the simplest first. From the notebook: two
loops reading every line, each with half the picture; a line with a paper's address
answered with what could not be done; the wish for faceit, mail, pages, programs asked for
in a sentence; and the question of how to give access and still feel safe.

**The home is where the notebook is kept whole and where what acts runs**: the folder, the
door, the keys, the pushes, the loops. The apps are for writing and looking. Today the home
is inside the Mac app; what it does is moved into Core as it is touched, so it can run by
itself on a machine that stays on, and be run and tested without a screen.

**A loop is a sentence, carried out one of two ways.** Kept in mind, part of the one
reading of each line. Or as a program, a small piece of code the home runs. Which way is
the proposer's shaping; setting it is the owner's hand.

**One reading.** An originator reads what lands once, with every sentence woken by a line
kept in mind and the whole notebook in view. Built 10 November: the loops woken by a line,
of one originator, run as one session, under the oldest of them; a loop on the clock runs
by itself. The reading touches nothing outside.

**Programs run with nothing but what they were given**: the door, under their own name, and
the reach they were granted. No files, no network beyond it, no keys. To be built, small
first: code in a little interpreter that can call only what it was handed.

**Reach is the owner's grant outward**, as a grant is inward: where a program may go, and
with which key. The key stays with the home and the program never sees it. Every use leaves
a receipt.

**In freely, out on the owner's word.** What comes in lands as a capture under its source's
name: a fetched paper beside the line that pointed at it, a match, a mail. What goes out
goes only on the owner's word: a line they wrote, a tap, or a standing allowance they put
on a reach. So nothing that reads a stranger's page ever holds a way out, and a link is
opened when it is in the owner's line, never one a fetched page put in an originator's.

**What a line points at is opened and kept beside it.** Built 10 November. A line of the
owner's with a link in it points at a page, a paper. The home, the owner's own Mac, opens
exactly that address and keeps its words in the notebook's media, attached to the line with
its title and where it came from, as the owner's event from that Mac. Only links in the
owner's own lines, never one in a line someone else wrote or in a page that was fetched;
only addresses out on the web by name, never this machine or this network, and a redirect
only to where it could have gone anyway; nothing of the owner's is sent. What is kept wakes
the reading like anything that lands; `read_kept` hands it the words, said to be the page's
own and no instruction. Pages and PDFs; a video's transcript is not opened yet.

**A reading is handed what it needs as it starts**, built 10 November: what is new to its
hand as whats_new will say it, the days those lines are on as the page reads, and the
beginning of anything newly kept beside one. It starts at the thinking and not at the
looking around; the one look it still takes is what marks things as seen.

**What a dropped link becomes.** With the page kept, a sentence kept in mind has the reading
make a thing of it, a paper, a talk, a book, with what is worth knowing as its facts. Two
facts a thing's page draws in their own way: `about`, a few plain sentences, as a paragraph;
`source`, an address, as a link. The pages its lines pointed at are on it too, to read
there whatever becomes of the address.

**Order.** The one reading, built. Opening what the owner's lines point at, built. Then
programs and reach, faceit first. Then pages, on the same footing as programs. The home as
a process of its own when one of these needs it.

## A kind's shape, the design

Decided and built 10 November. Said by the owner that day: a shape is a type that is made,
filled and drawn. A kind was one word on a thing, and nothing said what a paper has, so
each came out with whatever facts its maker happened to write, under whatever names.

**A shape says what the things of a kind have, in order, and what each is**: for a paper,
about, a few sentences; by; when; source, an address. That is all it holds.

**It is found by its kind's word**, as a tag is by its own, so every thing already called a
paper is of the paper shape, and nothing migrates. Anyone through the door says what a kind
has; the newest word stands; only the owner drops it. Until someone says, a kind most
notebooks come to, a paper, an article, a talk, a book, a plant, a person, a project, has
its usual shape.

**A thing is made by its shape and drawn by it.** Whoever makes a thing of a kind is told
what such a kind has and fills it, under those keys, so the things of a kind are alike. A
thing's page is its shape's facts in its shape's order, each drawn by what it is: a few
sentences as a paragraph, an address as a link, the rest as rows. What no shape names comes
after, drawn by what it looks like. One row per key, the newest word, whoever put it. The
page of a kind says what the kind has, and shows each thing's short facts in that order.

**Not done, on purpose.** A shape that does something; a shape made of other shapes; the
owner saying a shape from the phone.

## Hands, the design

Decided and built 10 November. From the notebook: a weeju and a Margo that were one being
through two keys; two loops sharing one memory of what had been seen, so one looking hid
lines from the other, and both writing to one file; and the owner's line that dotto should
be itself whatever tool or model people come through.

**An originator is who answers for something. A hand is how it acts at one moment**: a
session at the keyboard, a loop, whichever model. The owner's hands are the phone and the
Mac. Every event already says both, its author and what it came through; the hand is that
second word.

**Every notebook has one dotto.** It is there without being made, as a tag is: the one who
reads, answers and shapes. It is called dotto until it is named, and it wears the one colour
the app has. A new key is one more hand of dotto unless the owner says it is for someone
new: a source, Health, Mail, faceit, or another person.

**What has been seen is kept per hand.** A session and each loop have a place of their own
in the notebook, so each is told what is new to it, and each writes to a file of its own. A
hand looking for the first time starts from where its originator last looked at all. What
the originator's other hands did since is said briefly beside what is new, not as news
from someone else: it is the same being's own doing.

**dotto's memory is the notebook**: its page, its marks, its receipts. That is what makes it
one whatever comes through the door, and why nothing about a model is identity.

**Two ids that are one.** The owner says so with one event, `same`, and the fold reads
through it: everything the one did, and does, is the other's, in any order of arrival.
Nothing is rewritten; the files keep the names they were written under. A key the one holds
opens the door as the other from then on. Only the owner's word counts, and nobody is made
the same as the owner.

**A loop is a hand**, named from the loop: its own place, its own file, its receipts under
it. Only a source needs to be an originator of its own.

**Not done, on purpose.** A hand's model or tool as anything but a word in a receipt; hands
that are told apart on the page; a ceremony for naming.

## Lines stand somewhere, the design

Decided 10 November. Read since that day by every build; nothing writes it yet, so that no
build ever meets a reply it would show as a loose line. From the notebook: a reply that could not carry a photo, be
a todo, be linked to, be found, or be fixed by the one who wrote it; the owner's line of 9
November that every message is one thing, appearing in different places; and the wish to
talk to a page from inside it.

**There is one kind of written thing, a line, and where it was said is part of it.** Said
nowhere, it is on its writer's days: the owner's on the page, an originator's on its own
page. Said on the owner's days by someone else, it is the walk, the booking. Said under a
line, it is a reply. Said under a thing, it is something said on that thing's page.

**Where a line was said is part of the capture and never changes; what it connects to is a
link**, placed afterwards by anyone and taken back. A reply's place is the first; a thread,
a citation, a belonging are the second. A line under a line that points at another line
cites it; a line on its own days that points at an earlier one carries on from it.

**A reply is a full line**: photos, facts, a todo, links, search, a change by its writer. It
may answer a reply; the conversation shows flat under its line, and each reply knows what it
answers. Whoever wrote a line changes it; they or the owner drop it.

**Nothing migrates.** The replies already in the files read as lines under lines. Only where
a line was said is kept; the top of a conversation is worked out, since the whole log is here.

**Read first, written second.** Step one, 10 November: a line that says what it was said
under is read as a reply in that line's conversation, beside the replies written the older
way; a change to it or its being dropped is a change to a reply or its being taken back,
by its writer, or dropped by its writer or the owner; an answer knows the reply it answers;
what is new tells of it as a reply; it may arrive before what it was said under. A line
said under a thing is kept in the file and shown nowhere yet. Step two, the same day, once both apps were
on a build that reads: the phone and the door write a reply as a line that says what it was
said under; a reply written under a reply, in the inbox or through the door, answers that
reply; its writer changes it and drops it through the door as any line of its own. Still to
come: a reply that carries a photo, a fact or a todo is kept in the file and not yet shown,
because the conversation is still drawn from what a note was; the reply and inbox screens
are redrawn when it is.

**Not done, on purpose.** The screen for talking to a thing, which comes with pages.

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

- A shape that does something: a todo that ticks, a streak with its run and its breaks,
  elements collected. A kind's shape says what its things have and how they are drawn; a
  page that acts is the programs piece, and stands on it.
- Pages as definitions over shapes.
- Lines stand somewhere: read and written since 10 November. A reply as a full line on
  the screen, with its photos, facts and todo, is what is left; see above.
- A named place: a place fact is coordinates; what calls it the nursery is not built.
- Where loops run and pages are served, the home; media leaving the phone. Both parked,
  and both gate loops and pages.
- The old names: Margin and weeju in code, bundle ids and the conduct note. They stay
  until a deliberate rename.
