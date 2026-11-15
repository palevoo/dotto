# The door

What comes through the door, what it may do, and how the pages show it. As built in November
2026; it changes as it is used. The folder all of this is written into is in `format.md`.

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
`set_fact`, `set_shape`, `list_shapes`, `propose_loop`, `list_loops`, `write_line`, `add_line`, `edit_line`,
`delete_line`, `choose_name`. Writes
land in the grant's own event file; no grant can touch
your lines, a grant changes or deletes only lines it wrote, and it takes back only marks it
placed: not your done, nor a link or a label someone else put there. Revoke the grant and the key
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

A grant is a key, and by default one more hand of dotto, the notebook's own originator: a
session, a bot, a loop, whichever model. dotto is there in every notebook without being made,
is called dotto until it is named, and wears the persimmon dot. What has been seen is kept
per hand, so a session and each loop are each told what is new to them, and what dotto's
other hands did since. Two ids that were one being, through two keys, are made one by your
word, "This is dotto" in the grant's menu: a `same` event the fold reads through, with
nothing rewritten. A grant for someone new, a source or another person, has a fresh id and
no name. An originator may write lines of its own, which make
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

Something to do wears one mark, the same wherever the line is drawn: a ring under its time
while it is open, filled and quiet once it is done. Tap it and the line is finished where it
stands; tap it again and it is open. Done is what closes a todo: the word is never taken off
for it, and a finished line no longer says it is to do or when it was due. The Todos page is
the same lines with the same mark, due first; a line finished today keeps its place until the
day ends, and a todo with no moment that has waited three weeks steps back into Someday,
never late. You say a line is to do, or is not, in its hold menu; that is a correction, and
the reading still marks most of them.

Two facts carry a moment. `at` is when something happens whether or not you do anything, an
appointment, a class: an event, never to do, and it passes by itself. `due` is when
something wants you: a todo to be done by then, or a plain reminder. What is coming, both
kinds, has a page reached from the calendar sheet, by day, and a ring under its day in the
calendar. The phone says it by itself, with no Mac and no network: an event the evening
before and an hour before, something due at its moment, with Done and In an hour on a
notice about a todo. The notices are worked out from the fold each time the notebook is
read, the soonest sixty, so a moment moved, taken off or finished needs nothing undone. The
phone writes the moments it has covered beside its push address, and the Mac sends its own
push at a due moment only to a phone that has not.

A thing with a `since` moment is a streak, and nothing about it is set by hand: its run is
worked out from the notebook each time it is shown. It runs one of two ways. Without: every
day counts unless a line that is with it carries `break`, with the moment it happened when
that was another day than the line's own; you state nothing while it holds. With (`counts`
with): a day counts when a line is with it, a walk, a page read. A `span` is how long it is
meant to run; `ended` stops it; a newer `since` begins it again. Its page says the run in
days, a few quiet words, and every day since it began as a dot, seven to a row: ink for a
day that counts, an empty ring for one that broke, today in the one colour; a dot with a
line behind it leads to that line. Hold the number to stop it or begin again. It never
counts at you and never asks to be kept. Every list of lines, on a thing's page and among
what is coming, now says what each line is in the same quiet words as its day does.

A kind of thing has a shape: what a paper, a plant, a person has, in order, and what each
is. `set_shape` says it and `list_shapes` reads it; the newest word for a kind stands, you
drop it with a hold on the kind's page, and until someone says, the kinds most notebooks come
to have their usual shape. Whoever makes a thing is told what its kind has and fills it, so
the things of a kind are alike; a thing's page is its shape's facts in its shape's order, a
few sentences as a paragraph, an address as a link, the rest as rows, and whatever no shape
names after them.

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

A line of yours that was read and had nothing said under it wears a small dot under its time,
in the reader's colour, on today's page: read and nothing to say, told apart from a line
nobody has got to yet, with the home asleep or the line still on its way. A reply is its own
proof and shows no dot.

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
