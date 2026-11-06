# The system

A sketch, written 6 November 2026, after the first quote from a book. Nothing here is
decided. It tries to name the parts that keep showing up, so that the next things built
are parts of one thing rather than features.

The three fixed statements still hold and this is all under them: writing costs nothing,
your words are yours, meaning comes later.

## 1. The measure of a capture

The best capture is the one that is already part of the activity. A marker on a page of a
book is the measure for a quote: the hand is already on the page, the gesture is the
reading itself, and nothing is taken out. Every capture is judged against the gesture that
the activity already has, and the distance from it is the cost. Taking out a phone is a
cost. Opening an app is a cost. Choosing anything is a cost. A screen to dismiss is a cost.

Three kinds of capture, by how far they are from the activity:

    inside      the gesture is the activity: a highlight while reading, a word while
                walking, a photo while looking. The phone, when it is used at all, is
                already in the hand.
    ride-along  something already produced by the activity is caught on its way: the
                screenshot already taken, the photo already in Camera, the page already
                open in Safari. Share and drop are this.
    automatic   nothing is done at all: the walk from Health, the booking from the mail,
                the order from the shop, the game from the server. A feed.

The direction of work is always from the top of that list downward: make inside captures
need less, turn intentional captures into ride-alongs, turn ride-alongs into feeds where a
feed is honest.

## 2. The register of captures

Kept here and revised as each one moves. Steps count touches after the activity's own
gesture; "measure" is the best physical or existing equivalent.

    capture             how today                              steps  measure                       next
    words               Action button, type, Return            2      a pencil                      fine
    voice               Action button or mic, speak, stop      2      saying it aloud               stop on silence
    photo               Action button or camera, shutter       1-2    looking                       fine
    quote, while read   camera, hold, select, Quote, Return    5      a marker on the page          hold from the Action button; or Scan Text
    quote, from photo   open, select, Quote                    3      the same                      fine for old photos
    screenshot / page   share sheet, Margin                    2      dropping it in a chat         drop on the page; a Shortcut on Back Tap
    photo from before   camera, library, pick                  3      a shoebox                     fine
    walk                nothing                                0      a pedometer                   built
    video journal       not built                                     talking to a camera           start, stop, words after
    book on the shelf   a photo of the cover                   1      putting it on the shelf       a record made from the cover
    wine                a photo of the bottle                  1      the same                      the same
    plant progress      a photo, linked to the last one        2      looking at it                 the link made for you
    mail picked up      a line                                 2      ticking a list                a loop that waits for it
    booking, calendar   not built                                     the invitation itself         a feed from mail
    expense             not built                                     the receipt                   a feed from the bank
    game played         not built                                     the match record              a feed from the server
    order, client       not built                                     the order itself              a feed from the shop

Columns to add as they earn it: quality of what is caught, what it costs the battery,
what it needs from outside.

## 3. What a capture is made of

Every capture, from any of the three kinds, lands as the same thing: a line, by an author,
at a moment, in a place, with media if it has any. That is already so. What the sketch adds
is that a capture may also carry:

    kind     what the way in already knows it is: a walk is a walk, a quote is a quote,
             an order is an order. The owner never says this; the gesture or the feed
             says it. Meaning still comes later, for everything the way in does not know.
    record   the shape the kind brings with it: the walk's distance, the quote's book,
             the order's items. Small, on the line, readable by whatever shows or asks.
    source   where it came from, when it was not the owner's hand: the feed, the app
             shared from, the page it was dropped from. Provenance, for later trust.

So a capture is: what (the words, picture, sound, record), how (the gesture or the
trigger), for what (the kind, when the way in knows it), by whom (the author), and from
where (the source). The notebook holds all five without the owner naming any of them.

Feeds are authors. A feed is a small program holding a grant, writing lines of its kind
into a file of its own, exactly as the Claude Code session does today. The bank, the shop,
the mail, the game server: each one a grant in the Mac's window, each revocable with one
click, each visible in Logs. Nothing in the app knows a feed from a person. That is the
whole extension story for capture, and it exists.

## 4. What happens after

Most lines want nothing, and that is the default forever. For the rest, the things that
can happen to a line, from what is built to what is not:

    built     label     a word on a line, for finding later
              link      a later line carries on from an earlier one; may close it
              note      a reply under a line, by anyone, removable by the owner
              edit      the author changes or deletes their own line
              inbox     an author learns what happened since it last looked
              push      a note reaches the phone

    not yet   record    a value on a line, read by views and queries, written by
                        whoever has the right: the feed, the agent, a loop
              view      how a kind shows: a card for a verb, a shelf for books, a
                        board for orders. Declared, not coded; drawn by the app in its
                        own style, so it feels native and can do nothing else
              query     lines by kind, label, time, place, record: all wine, all open
                        orders, every quote from this book
              time      a moment as an event: a line that comes back, a reminder,
                        a wait. The mail to pick up waits until it is picked up
              loop      when this, do that: when an order lands, make the packaging
                        line and wait two days; when a quote lands, link it to the
                        book. A loop is a program, holds a grant, and runs somewhere
              out       leaving the notebook: an email sent, a charge made, a page
                        published. Every crossing shown in Logs before and after,
                        each with its own consent, nothing silent

Those six are the primitives that the programmable ideas need: the game, the verb cards,
the bookshelf, the wine shelf, the small business. They are the same six in every case.

## 5. Who does things

Three kinds of author, and the rule that holds them all: a line belongs to whoever wrote
it, and anyone other than the owner writes beside the owner's lines, never on them.

    the owner     captures. Never files, never sorts, never configures a loop by hand
                  unless they want to.
    the agent     reads through the door, marks, answers what asks, keeps a page, and
                  can make kits (below) out of a conversation.
    programs      feeds and loops. Each is a grant: an author with an id, a page, scopes
                  that say what it may do, a log of what it did, a key that can be
                  revoked. Code never runs inside the phone app; it runs where the
                  door is and touches the notebook only through it.

That last line is the security model and it is already the architecture. Isolation,
revocation and visibility come from the grant, not from a sandbox we would have to build.
What is new is that scopes grow to cover records, time, and crossings out.

## 6. Kits

A kit is a bundle: a kind, its record shape, its view, the loops that serve it, the
captures that feed it, and the grant it runs under. Examples that have come up:

    bookshelf   kind book from a cover photo; view: a shelf; query: by book; loop: a
                quote links to its book; capture: the quote
    wine        kind bottle from a label; view: a shelf; record: where it was had, with
                whom
    words       kind word or verb; view: a card; loop: ask again in three days; view: a
                game that flips or matches
    plants      kind plant; loop: a photo links to the last of the same plant; view: a
                strip of its photos in time
    the sale    kinds order and client; loops: packaging line, welcome email, reminder;
                out: a page, a charge, an email; view: a board of open orders
    games       kind match from a feed; view: a run of results

A kit is made by anyone: the owner by asking, the agent out of a conversation, someone
else and shared. Installing one is adding a grant. Removing one is revoking it; the lines
it wrote stay, as lines.

## 7. The floor

What everything above stands on, all of it built: the event log, one writer per file;
media by hash; authors, names and grants; the fold; the day pages; the door; the inbox;
devices and pushes; the build stamp. Two parts of the floor are not built and everything
in §4 waits on them:

    the runner   where loops and feeds run. One Mac, for now, the one that serves the
                 door. The same Mac can carry the tray that takes drops.
    secrets      a key for a feed or a crossing, kept the way the push key is kept: in
                 the Mac's keychain, never in the folder.

## 8. Next iteration, proposed

Build one kit end to end and let it force the primitives into existence: record, view,
query, loop, in that order, with time and out left for the second kit. The bookshelf is the
candidate: the quote already exists, a cover photo is one capture, the shelf is a view
worth having, the quote-to-book link is a loop with no crossing out, and the agent can be
the first program that runs it. The sale is the second kit, because it needs time and out,
and those two deserve their own design under their own consent.

The game, if still wanted, is a view with no record behind it worth keeping, which makes
it a fine first test of the view half alone, before the bookshelf.
