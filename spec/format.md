# The folder, as a format

What a notebook is on disk, written down so that another program, in any language, can read
one and take part in one. This is version 1, the `version` in `notebook.json`. It grows by
addition only: a kind never changes its meaning, and a reader passes over what it does not
know.

`spec/sample` is a small notebook with the day pages a reading of it comes to. A program
reads the format rightly when its reading of the sample's events gives those pages.

## The folder

    <notebook>/
      notebook.json                    who owns it
      events/<author>.<device>.jsonl   what happened: one writer per file, append-only
      media/<hash>.<ext>               photos, voice, kept pages, named by their content
      days/YYYY-MM-DD.md               derived: the reading, as pages anyone can open
      devices/<device>.json            where a phone can be reached with a notification

Everything that counts is in `events` and `media`. `days` can be deleted and made again.

## notebook.json

    { "id": "01KJPRZB00…", "created": "2026-03-02T08:00:00.000Z", "owner": "me", "version": 1 }

`owner` is the author id of the person whose notebook it is. It never changes.

An author is whoever writes: the owner, the notebook's own originator, Health, another
person. The apps and the other documents say originator; the field is `author`.

## Event files

One file per writer per device, named `<author>.<device>.jsonl`. In the name, anything that
is not a letter, a digit, `-` or `_` is written `_`. A writer appends to its own file and
touches no other, so two writers never write the same bytes and there is nothing to merge.

A file is UTF-8, one event per line, each line one JSON object, ended by a newline. Nothing
is ever rewritten. A line that cannot be read, a write cut short, is passed over by its
reader and costs only itself. Blank lines are nothing.

    {"at":"2026-03-02T12:30:00.000Z","author":"me","device":"phone","id":"01KJQ8DQA0…","kind":"entry.create","payload":{…}}

    id        a ULID, made by the writer at that moment: 26 characters, the first 10 the time
              in milliseconds, so sorting ids sorts by time
    author    who wrote it: an id, not a name. A name is chosen later with name.set
    device    which device or hand it was written from
    at        when, ISO 8601 in UTC with milliseconds. A reader takes one without them too
    kind      one word from the list below
    payload   an object whose fields follow from the kind

Core writes keys sorted and does not escape slashes, so a line is the same bytes on every
device. A reader need not care.

An id's time is the time its maker made it, which is not always the moment it is about: a
photo from June brought in today has today's id. A moment is always a field, never read
from an id.

## Taking part

Choose an author id and a word for your device. Append events to
`events/<author>.<device>.jsonl`, each with a new id. Never write to another file, and never
change a line once written. That is all the folder asks.

What you write is read by the rules below, which say whose word counts for what. Nothing in
the folder proves who wrote a file but its name: whoever can write to the folder can write
any file. Who is let into the folder is the owner's to decide. Through the door, the Mac
app's local server, a key decides it: see `grant.create`.

## The kinds

Fields with `?` may be absent. "Counts from" says whose event the reading takes; anyone
else's is passed over.

Lines

    entry.create   {entry, text, at, loc?, page?, under?}
                   A line. `entry` is its id, `at` the moment it began. `loc` is
                   {latitude, longitude, accuracy?}. `page` is whose page it lands on, the
                   writer's own when absent: a walk from Health names the owner. `under` is a
                   line or a thing it was said under.
    entry.edit     {entry, text}         The whole new text. Counts from the line's author.
    entry.delete   {entry}               Final. Counts from the line's author, and from the
                                         owner for a line on the owner's page.
    media.attach   {entry, hash, mime, w?, h?, dur?, title?, source?}
                   A file in `media`, by the SHA-256 of its bytes. Counts from the line's
                   author. `title` and `source` are for a page kept beside a line.

Replies

A reply is a line: an `entry.create` whose `under` is the line, or the reply, it answers.
The apps and the door write replies this way. The older shape is still read:

    note.add       {entry, note, text}   A line under someone's line, by anyone.
    note.edit      {note, text}          Counts from the note's author.
    note.remove    {note}                Counts from the note's author and from the owner.

Marks, placed afterwards by anyone

    link           {from, to}            Joins two things by id: a later line to an earlier
    unlink         {from, to}            one, a line to a thing it belongs to. One per pair;
                                         the newest of link and unlink stands.
    label.attach   {entry, label}        Read as a link from the line to the tag of that word.
    label.detach   {entry, label}        Read as the unlink.
    done           {entry, by?}          The line is finished, by the line `by` when one
    undone         {entry}               finished it. The newest of the two stands.
    link.add       {later, earlier, closes}   The older shape of link and done. Still
    link.remove    {later, earlier}           read; nothing writes it.

Things

    thing.set      {thing, name, kind?}  Something lines belong to: a plant, a book, a person.
                                         Set again only by whoever made it; the newest stands.
    thing.remove   {thing}               Final. Counts from its maker and from the owner.
    fact.set       {on, key, value}      A key and a value on a line or a thing. One per
                                         writer per key; that writer's newest stands.
    fact.remove    {on, key, of?}        Counts from the fact's writer, and from the owner,
                                         who names whose in `of`.
    shape.set      {kind, has}           What things of a kind have, in order. `has` is a list
                                         of {key, is, says?}; `is` is one of text, words, link,
                                         number, moment, span, place. The newest stands.
    shape.remove   {kind}                Counts from the owner.

A fact's value is one object with one of these:

    {"number": 2, "unit": "kg"}    {"words": "potted"}    {"moment": "2026-03-01T09:00:00.000Z"}
    {"span": 2460}  in seconds     {"place": {"latitude": 52.37, "longitude": 4.9}}

A tag is a thing whose id follows from its word, so every writer lands on the same one with
no lookup: time zero, and for the other ten bytes the first ten of the SHA-256 of the word,
trimmed and lower-cased.

A line a source says about a moment, a walk from Health, has an id that follows from the
source and the second it began, so two readers of one source write the same line and it is
read once. Its time is that second, and its other ten bytes are the first ten of the SHA-256
of the author id, a zero byte, and the second since 1970 written as a decimal number.

What it was like

    conditions.set     {entry, source, temperature?, sky?, daylight?, humidity?, wind?, windFrom?,
                        rain?, rainBefore?, low?, high?}
                       The weather where and when a line was written, said afterwards. Metric.
                       `sky` is the World Meteorological Organization's code. The newest stands.
    conditions.remove  {entry}           Final. Counts from the owner.

People and keys

    name.set       {name}                What the writer is called from now on.
    grant.create   {grant, author, name, device, hash, may}
                   The owner hands `author` a key to the door. `hash` is the SHA-256 of the
                   key, never the key. `may` lists what it may write: notes, labels, links,
                   lines. Counts from the owner.
    grant.revoke   {grant}               The key stops opening the door. Counts from the owner.
    same           {author, same}        Two author ids are one being. Counts from the owner.

Loops

    loop.set       {loop, name, grant, wake, at?, brief?, turns, budget}
                   A sentence kept and run. `wake` is "line" or "clock", with `at` as "HH:MM"
                   for the clock. Counts from the owner; the newest for a loop stands.
    loop.stop      {loop}                Counts from the owner.
    loop.propose   {loop, name, grant?, wake, at?, brief?, turns, budget}
                   A loop someone else asks for. It waits for the owner's loop.set of that id.
    loop.ran       {loop, run, ok, turns?, cost?, summary, startedAt, endedAt}
                   The receipt for one run.

Receipts

    visit          {what, count, since?, label?, entry?, hash?, seen?, words?}
                   Someone read: what they asked for and how much came back. `what` is one
                   of days, lines, photo, kept, inbox, things, loops, search. `seen` is how
                   long each event file was at that look.

## Reading

Take every event from every file and put them in order of id. Then:

- A kind you do not know is kept and passed over. So is a value you do not know.
- An event about a line that has not been created yet waits for it.
- An event whose id was read already is passed over, and so is an `entry.create` for a line
  that exists.
- Whose word counts is in the list above. A line belongs to whoever wrote it: only they
  change it. Everything else on a line is beside it, in its writer's own file, and can be
  taken off without touching the line.
- A line is on the day its `at` falls on, in the reader's own calendar, and on the page
  `page` names, or its writer's.
- What a link means follows from its ends: a line to an earlier line carries on from it, a
  line to a thing belongs to it, a note to a line cites it.

The apps read a few fact keys in a set way: `todo`, `due` and `at` on a line, and on a streak
`since`, `counts`, `span`, `ended` and `break`. `spec/design.md` says how, under Shapes.

## Media

`media/<hash>.<ext>`, where `hash` is the lower-case hex SHA-256 of the file's bytes and the
extension follows from the `mime` of its `media.attach`: jpg, png, heic, m4a, mov, mp4, md,
txt, and bin for anything else. A page kept beside a line is `text/markdown`.

## Days

`days/YYYY-MM-DD.md` is the reading written out, one file per day, for anyone to open
without an app. It is made from the events and never read back.

    # 2026-03-03 · Tuesday

    ## 18:40
    First loaf out. Dense, good crust. Why dense?

    > dotto · 18:41
    > A young starter, most likely: it is two days old. Give it a week of feeding.

    _with The starter_

    #bread

## Devices

`devices/<device>.json` is where a phone says how it can be reached: `device`, `token`,
`environment` (development or production), `topic` (the app's id), `updatedAt`, and
`scheduled`, the notices the phone says itself. It is not an event and holds no words.

## The sample

`spec/sample` is two days of a notebook: the owner's lines from a phone, what the notebook's
own originator made of them from a home, a walk from Health, the weather on one line, a page
kept beside another. Its `days` are the reading in UTC, in English.

To check a reader: read `spec/sample/events`, write the days, and compare them with
`spec/sample/days`. Core does this in `Core/Tests/CoreTests/FormatTests.swift`, and also
writes every line back to check it comes out as the same bytes.

## Not here yet

- Nothing is signed. A file's name says who wrote it, and nothing proves it.
- The door, the local server that hands the notebook to an agent by a key, is in
  `spec/door.md`.
