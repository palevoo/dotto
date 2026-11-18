#!/bin/sh
# The site's fonts, cut down to what its pages use, so they can be served from the site's
# own host and are small. Run it when a face, a weight or the letters wanted change:
#
#     pip install fonttools brotli     # once, in an environment of your own
#     design/fonts.sh
#
# It takes the four families from google/fonts at the commit named below, all under the
# SIL Open Font License with no reserved names, and writes into site/fonts/:
#
#   newsreader-400       a person's words: weight 400, optical sizes 18 to 72, English
#   newsreader-400-more  the same face for accented letters, fetched only when one is shown
#   newsreader-500       the privacy page's heading
#   geist                the system's words, weights 400 to 500
#   geist-mono-400       times
#   LICENSE.txt          the licence, with each family's copyright line
#
# Each file's name carries the first eight characters of its hash, since the site tells
# browsers to keep a font for a year: a font that changes gets a new name, and the pages
# that name it are changed by hand. The name "dotto" is set in Shantell Sans, three
# letters of it, small enough to sit inside the page; the script prints that as a data
# address to paste into the pages' @font-face.
set -eu

commit=7af0d90b4d532ffa4b041937b560c6df4e7b1e95
here=$(cd "$(dirname "$0")" && pwd)
out="$here/../site/fonts"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

get() { curl -sSfL -o "$work/$2" "https://raw.githubusercontent.com/google/fonts/$commit/ofl/$1"; }
get "newsreader/Newsreader%5Bopsz%2Cwght%5D.ttf" newsreader.ttf
get "geist/Geist%5Bwght%5D.ttf" geist.ttf
get "geistmono/GeistMono%5Bwght%5D.ttf" geistmono.ttf
get "shantellsans/ShantellSans%5BBNCE%2CINFM%2CSPAC%2Cwght%5D.ttf" shantell.ttf
for family in newsreader geist geistmono shantellsans; do get "$family/OFL.txt" "$family.txt"; done

# One weight, or a span of weights, out of a variable font.
pin() { python3 -m fontTools varLib.instancer "$work/$1" -o "$work/$2" --no-recalc-timestamp -q "${@:3}"; }
# The letters wanted, as woff2, with the copyright and the licence kept inside the file.
letters() {
    python3 -m fontTools subset "$work/$1" --output-file="$work/$2.woff2" --flavor=woff2 --no-hinting \
        --no-recalc-timestamp --drop-tables+=meta --name-IDs=0,1,2,3,4,5,6,13,14 \
        --layout-features=kern,liga,calt,ccmp,locl,mark,mkmk,tnum "${@:3}"
}

english="U+0020-007E,U+2010-2014,U+2018-201D,U+2022,U+2026"
accents="U+00A0-00FF,U+2212"

pin newsreader.ttf newsreader-400.ttf wght=400 opsz=18:72
pin newsreader.ttf newsreader-500.ttf wght=500 opsz=26
pin geist.ttf geist-span.ttf wght=400:500
pin geistmono.ttf geist-mono-400.ttf wght=400
pin shantell.ttf shantell-700.ttf wght=700 BNCE=0 INFM=0 SPAC=0

letters newsreader-400.ttf newsreader-400 --unicodes="$english"
letters newsreader-400.ttf newsreader-400-more --unicodes="$accents"
letters newsreader-500.ttf newsreader-500 --unicodes="$english"
letters geist-span.ttf geist --unicodes="$english,U+00B7"
letters geist-mono-400.ttf geist-mono-400 --unicodes="U+0020-007E"
letters shantell-700.ttf dotto --text="dotto"

mkdir -p "$out"
for name in newsreader-400 newsreader-400-more newsreader-500 geist geist-mono-400; do
    hash=$(shasum -a 256 "$work/$name.woff2" | cut -c1-8)
    rm -f "$out/$name".????????.woff2
    cp "$work/$name.woff2" "$out/$name.$hash.woff2"
    echo "site/fonts/$name.$hash.woff2  $(wc -c < "$work/$name.woff2" | tr -d ' ') bytes"
done

{
    echo "The fonts in this folder, and the three letters of Shantell Sans inside the pages, are"
    echo "cut down from these families and are under the SIL Open Font License, Version 1.1."
    echo
    for family in newsreader geist geistmono shantellsans; do head -1 "$work/$family.txt"; done
    echo
    sed '1,/^$/d' "$work/newsreader.txt"
} > "$out/LICENSE.txt"
echo "site/fonts/LICENSE.txt"

echo
echo "The name, for src in the pages' @font-face for \"Shantell Sans\":"
echo "url(data:font/woff2;base64,$(base64 < "$work/dotto.woff2" | tr -d '\n')) format(\"woff2\")"
