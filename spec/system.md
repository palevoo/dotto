# The system

The direction, as said on 6 November 2026. No implementation here; that comes after this
is understood.

## The idea

We are building an operating system for a person's life and work, where everything begins
with capture. The use cases touched so far, quotes, plants, books, wine, walks, games, a
video journal, the olive oil sale, a repair shop, are not features. They are evidence of
what the components have to be. A great tool is one anyone can use for many different
needs, so the job now is to understand the components and how they combine, cooperate,
plug in and unlock each other, rather than to keep adding features one at a time.

## Capture

Different people and environments need different captures. Some are direct and
intentional. Some are indirect and automatic, like a booking arriving by mail. Some just
hang there with nothing updating them, like having gone to pick up the mail.

A capture is at least a what, a how, and a for what, and probably more.

The goal is the most intuitive, clean and powerful set of default captures, plus a way for
anyone to customise, extend or add their own: the bank for expenses, the game server for
matches. Every capture is judged against the most convenient form the activity could
possibly have, the marker on the page of a book being the example for a quote, with no
limit on how it might be solved.

A running record of every capture idea is kept, with its trade-offs: the current version,
the number of steps, the quality.

## After capture

Labelling happened to be the first thing built, but it is one of many: sorting,
organising, processing, saving, notifying, recycling, doing nothing. A new order or client
in a small business is a capture that happens by itself, and what follows, packaging, a
reminder, a welcome email, belongs here. This needs a robust set of primitives and a design
that supports all sorts of needs, not a list of actions.

## Underneath

The primitives that make both possible: not only connection to the outside, such as a
domain or a payment, but the whole toolset in between, storage, processing, and whatever
else turns out to be needed.

## An open question

A single capture is often several things at once, an idea and an intent, say, and those
things have different lifecycles. The design has to account for that. How is not decided.

## What comes next

Stop iterating. Conceptualise the next iteration as clear components and primitives, how
they relate and work for different needs, following the most beautiful patterns and
without limiting capabilities. Direction first, implementation later.
