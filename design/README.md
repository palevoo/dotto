# The look

What Dotto looks like, kept in one place. What is drawn elsewhere is made from here.

## The dot

Dotto's mark is a dot drawn by hand. It is four arcs that meet at four points, one on each
side of a box. Where a point sits along its side is one number, so four numbers, a
proportion and a turn are a dot, and no two need be alike. Everyone can have their own.

`dots.json` has twelve of them. The first is Dotto's own, in persimmon. dotto dev wears the
same dot in plum.

    { "meets": [58, 55, 53, 46], "proportion": 1.09, "turn": -8 }

- `meets` is where the arcs meet on the top, right, bottom and left sides, in hundredths:
  across from the left on the top and bottom, down from the top on the sides. Four fifties
  is a circle.
- `proportion` is width over height.
- `turn` is degrees, clockwise.
- `size`, at the top of the file, is how much of a sheet a dot takes.

The drawing itself is `Core/Sources/Core/Dot.swift`, so the apps draw the same dot the
icons have. An originator's own dot follows from its id, as its colour does.

## The colours

`tokens.json`. A cool near-white ground, neutral black text, hairlines barely there, and
nothing coloured but the dot. There are eight colours a dot can wear: persimmon, yolk, leaf,
teal, sky, cobalt, plum and pink. Yolk is pale on white.

A value written `"{dot-persimmon}"` is that colour, under another name.

## The type

What the system says is in a grotesk, a person's words stay in a serif, and times are in a
mono: Geist, Newsreader and Geist Mono on the site, and the system's own faces on the
phone and the Mac. The name is written by hand. Until its letters are drawn it is set in
Shantell Sans, which has an open licence (OFL).

## Making things from it

    swift run --package-path design dot

That writes:

- the app icons: the phone's in light, dark and for tinting, the Mac's and dotto dev's at
  every size the Mac asks for;
- `assets/dot.svg` and `assets/dot.pdf`, Dotto's own dot alone;
- `assets/icon.svg` and `assets/icon-dark.svg`, the dot on its sheet;
- `assets/dots/01.svg` to `12.svg`, each dot, in the colour of the text around it;
- `Core/Sources/Core/Dots.swift`, the dots for the apps;
- the dots inside `site/index.html` and `site/privacy/index.html`, where their style marks a
  place for them, and `site/icon.svg`.

A file that already says the same is left alone, so a run with nothing new changes nothing.

The site's fonts are made apart, by `design/fonts.sh`, which needs `fonttools` and `brotli`
from pip. It cuts Newsreader, Geist and Geist Mono down to the weights and letters the pages
use, writes them into `site/fonts/` under names that carry their hash, and prints the three
letters of the name's face for the pages to hold inside themselves. The pages name the files,
so a font that changes is a change to the pages too.

The program is built on Core, and Core needs its `Dots.swift` to build. If that file is
lost, take it back from git before running.

To change the look, change a number or a colour in the two JSON files, run it, and look at
what it wrote.

## Not here yet

- The apps' colours and the site's are still typed where they are used. They are to be
  written from `tokens.json`.
- The icons to choose from on the home screen.
- The name by hand in the Mac's window, which has it in the system's serif. It needs the
  face inside the app.
- The name as a file, which waits for its letters.
- Colours for print. The PDF is in screen colours.
- Who may use the name and the dot. The code is under the MIT licence, which says nothing
  about a name or a mark.
