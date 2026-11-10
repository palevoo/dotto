# Study: from a capture to what needs doing

10 November 2026. Asked for by the owner in place of starting on programs: step back, look
at where we are, at what others have done, at the notebook, and find the best way forward.
Research by dotto in four passes: products that turn captures into structure, interfaces made
by agents or users, what makes todos, reminders and collections feel good on a phone, and a
reading of our own code along three journeys. Nothing here is decided. What is mine is said
to be mine. Claims the passes could not check are marked.

## The priority, in the owner's words

A seamless way from capture to whatever needs to be done. For a todo, a completed todo. For
a reminder or an event, not to be forgotten. For Project Mendeleev, a way to explore the
table and keep track. Consistent, and it should feel amazing. No over-engineering. Building
a few by hand before designing a system for them is a valid path. One of the things to
build is dotto's own page.

## Where the three journeys stand today

Read from the code, with file and line in the session's audit.

**A todo.**
- A line is a todo when dotto puts the fact `todo` on it. The owner cannot make one, on the
  phone or the Mac.
- It shows as the word "todo" in a quiet row under the line, and on a Todos page reached
  through the calendar sheet.
- It is finished by a hold on the Todos page, or by dotto when a later line says so. The day
  page and the line's page have no way to finish it. Nothing is a tap.
- Once done, the fact `todo open` stays on the line, and "due" stays on its row.
- The Todos chip disappears when nothing is open.
- Four open todos in the notebook are a week old or close to it: the office and the
  passwords, the TV, the tyres, the Lego box. Nothing has asked about any of them.

**A reminder or an event.**
- dotto puts a `due` moment on the line. Nothing tells an event from a deadline.
- One push is sent at that moment, by the Mac, if the Mac app is running and awake. A push
  more than a minute late is dropped and never sent. The phone schedules nothing itself.
- The push has no buttons. There is no page of what is coming.
- A line written on the phone while the Mac sleeps has no due at all until the Mac wakes.

**Project Mendeleev.**
- A thing with two numbers, both typed in by dotto. Nothing is counted from the lines.
- Its page is a list: time and words. No photos, no facts of the lines, no grid.

**Across all three.**
- The same action is a hold in one place and a button in another.
- A line is drawn four different ways: on the day, on Todos, on a thing's page, on dotto's page.
- From Return to dotto's mark there are two trips through iCloud, five seconds of waiting by
  design, and a cold start of the `claude` command.

None of these gaps is missing infrastructure for programs. Each is ordinary work on the
fold and the screen.

## What others found

**Structure from captures.**
- Ink & Switch's Potluck let people enrich plain notes with patterns. Their own verdict:
  parsing text after the fact was cumbersome, and non-programmers could not write the
  computations. Embark's views were hard-coded and they name that as unsolved.
- Tana, Anytype, Notion and Logseq started general. All carry the same complaint: setup
  before value, and a model people cannot hold in their head. Logseq's rebuild has taken
  years.
- Capacities started specific, with tasks as a fixed type. People use it. The cost: the
  ticking is welded to one type and cannot be given to another.
- Obsidian's Bases cannot see a task written inside a note. Facts the view cannot see is the
  recurring failure. We already draw unknown facts; keep that.
- Todoist and Fantastical show their guess on the words themselves, at once, undone with one
  key. Things parses a date only in the date field and is never wrong.
- The bullet journal has two behaviours and no more: a tick, and migration, the regular
  rewrite of open tasks where not rewriting one is how it is dropped.
- Capture everything and sort it out later did not survive as a product by itself: Rewind
  and Limitless were bought and shut in December 2025. ChatGPT retired its unprompted daily
  briefing in June 2026 and kept a plain page of scheduled tasks with pause and delete.

**Interfaces made by agents or users.**
- Three families. Data drawn by the app's own blocks: Raycast, Google's A2UI, Vercel's
  json-render. Web pages in a frame: Claude Artifacts, MCP Apps. Code in a sandbox:
  Scriptable, Roblox, Val Town.
- Blocks keep the look and cap the ceiling at the set of blocks. Web pages have no ceiling
  and drift from the look. Code has a high ceiling and rests on the sandbox.
- Raycast is the clearest account of order: built-in extensions in Swift first, the API
  afterwards, then the built-ins moved onto it.
- Apple, March 2026: updates to two apps that run generated code in a web view were blocked
  and a third was pulled. Data drawn by native blocks is the safe reading of the rules.
  This matters only once dotto ships through the store.
- Apple's own JavaScript engine has no public way to stop a program that runs away
  (unverified beyond the headers found). QuickJS does, and runs on Linux. This was the one
  thing I had left open in my earlier proposal, and the answer goes against it.
- Granting access outward, where it works: the code holds nothing, the host holds the key
  and does the fetching, hosts are named, the first run is a preview, and every imported
  item carries its source's id so a second run adds nothing.

**Feeling good.**
- Completing: one gesture, one small answer, and the item does not jump away. In Things it
  stays where it was until evening (from memory, unverified).
- Guilt: undated intentions should fade when left alone. Only dated ones should ever look
  late. Things has Someday; Sunsama archives what rolled over too long.
- Not forgetting: the only thing that fires with no network and no Mac is a notification
  the phone scheduled itself. 64 can wait at once. Since iOS 26 an app can ring a real
  alarm through silence and Focus (AlarmKit). Due is trusted because it repeats until you
  answer.
- Writing into Calendar without reading it means never being able to move the event. So
  dotto keeps the data and Calendar is at most a copy.
- Collections: fixed numbering so gaps show, an empty cell that invites, a first-time
  moment and nothing after. Merlin celebrates a new bird once and has no streaks. Theodore
  Gray's collection is loved for the ordinary object and its story. The periodic table is
  already a Pokédex.
- Consistency: one row grammar, one mark that carries state, type-specific detail one
  level down.

## What the notebook already says

- 2 Nov 22:22: todos subtly crossed out or completed, "what a post is in essence". The first
  ask, still the weakest journey.
- 5 Nov 15:45: "Unattended UX might highlight the natural flow of things." Watch what is
  done by hand, then build that.
- 5 Nov 08:28: do not demand a big start state before the tool helps. True for us as
  builders too.
- 6 Nov 09:38, Deutsch: an explanation that could explain anything explains nothing. A page
  system that could draw anything is the same.
- 9 Nov 11:17, Hamming: what appears to be a defect is an asset. Every page being a build
  is why every page looks like dotto.
- 9 Nov 22:45: collecting is a view over lines, not new storage. The data is done; only the
  experience is missing.
- 5 Nov, the Saturday harvest: planned, never mentioned again, and nothing asked. A system
  that keeps intentions should notice a silence.
- 9 Nov, the week read as one page: the review that catches what line-by-line reading
  misses already ran once, by hand.
- 10 Nov 14:11: a changelog per project. A fourth case of the same form: lines under a
  thing, drawn the way its kind wants.

## The options

| | How it works | Look | Ceiling | Cost now | Cost per new thing |
|---|---|---|---|---|---|
| A. By hand | Each experience written in Swift | Ours | None | None | A build |
| B. Blocks | A page is data naming a few native blocks | Ours | The blocks | Medium | A definition, or a build for a new block |
| C. Code | Programs in a sandbox, handed only the door | Ours if it returns blocks | High | High | A script |
| D. Web | dotto writes HTML, shown in a frame | Drifts | Highest | Medium | A page |

- A teaches the most and leaves nothing reusable unless written with care.
- B is where A leads if each hand-built piece is a block drawn from the thing's shape.
- C is right for loops that reach outside, on the Mac. It is wrong for the phone today: no
  safe stop on Apple's engine, the store's rules, and no case in the notebook that needs it.
- D is the natural form of one thing only: a public page, which is a web page anyway.

## What I would do, mine, undecided

**Build the three by hand, in order, and let the system fall out of them.**

1. **The todo that ends.** Sets the grammar everything else reuses.
   - One row, drawn the same on the day, on Todos, on a thing's page.
   - One mark in one place: hollow when open, filled when done. Tap it to finish, where the
     line stands. It stays put for the day.
   - Done closes the todo; nothing is left saying open.
   - Undated todos left alone fade into a someday fold. No red, no count.
2. **Not forgotten.** The phone schedules its own notifications from the fold, the soonest
   64, refilled whenever it runs. Done and Later on the notification. The same page as
   Todos shows what is coming. The Mac's push stays as a second path.
3. **Mendeleev.** The first number that is counted, not typed. The first grid. A cell that
   fills with the owner's photo, once. An element's page in the shape grammar we have.
4. **dotto's page.** A web page written by dotto from the notebook into a file. No frame,
   no bridge, no scripts. The changelog from the margin lines is its first real content.

**The rule for extracting**: when the same thing is written a third time, it becomes a
block or a function with a name. Not before. After Mendeleev we will know what a page
definition needs to say, because we will have three.

**What makes this not a dead end**: behaviour hangs off a fact, never off a kind. Anything
with `due` reminds. Anything done is struck. Anything with members counts them. That is
Capacities' mistake avoided, and it means the later move to pages as data renames things
and migrates nothing.

**What I would take back or leave.**
- My program runner of this morning. Nothing in the three journeys needs it. It returns
  with faceit, on the Mac only, with the grant contract above.
- `todo open` as a fact that outlives done.
- An inbox row for every fact placed. Marks belong on the line.
- The read dot and the todo mark as two different dots. One place for dotto's mark.
- Streak counters. The research is plain that counting days turns into anxiety. A streak
  shows its run and its breaks and never nags.

## Decided, 10 November

The owner's word: all up to dotto; seamless, no overloading, clean. So:

- The path: the three by hand, in the order above, extracting on the third repeat.
- The owner may say a line is to do or is not, in its hold menu. A correction, not filing.
- One `due`. With a todo it stays open until done; without, it is an event and passes.
- The weekly look and how loud a reminder is are decided when their piece is built.

Built the same day, the first piece: the todo that ends. One mark, a ring under the time,
tapped where the line stands, on the day, on Todos, on a thing's page and on the line's
page. Done closes the todo. Finished today keeps its place; three weeks with no moment is
Someday. Not built: the someday fold has not been seen with real lines, and the Mac shows
no todos.

Built the same day, the second piece: not forgotten. The owner's correction first: an
appointment is not a todo. So two facts carry a moment, `at` for an event and `due` for
what wants the owner, which the spec had named and nothing read; "one `due`" above was
wrong. A Coming page, the phone's own notices, the Mac stepping back. Not built: a copy
into Calendar; notices have not fired on a real phone yet.

Found on the way, there before, not solved: a page shorter than the screen and taller than
the room above the keyboard stops answering when the keyboard comes up. A new notebook's
first day would meet it. It goes when the page stops tracking its top row, which the pinned
date and the calendar need.

## Open, for the owner

- May the owner say "this is a todo" or "this is not" with a hold? It is a correction, not
  filing, but it is your rule.
- An event and a deadline: one `due`, or two facts? An event passes by itself; a deadline
  stays open until done.
- A line written while the Mac sleeps has no due. The honest fix is where the reading runs,
  the parked fork. A smaller one: the phone itself spots a date as the line is stored and
  proposes the due, dropped with a hold like anything else.
- How loud "not forgotten" is by default: one notification, a repeat until answered, or a
  ring for the ones that must not be missed.
- Whether the weekly look at what is still open, keep or drop, is wanted. It is the bullet
  journal's migration and the 8 November week page in one.
