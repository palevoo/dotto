#!/bin/sh
# Says to a build which commit it is made from, so an app can say which build is running and
# the repository can say which build it should be. And its build number: the moment of that
# commit, to the minute, so everything built from one commit, an app and what is embedded in
# it, carries the same number, and a later commit a higher one.
#
# It writes three names into a small header, and Xcode puts them into the Info.plist as it
# makes it (INFOPLIST_PREFIX_HEADER): DOTTO_COMMIT, DOTTO_CHANGED and DOTTO_BUILD, which the
# plists in project.yml name. Nothing is written into a finished Info.plist. That was tried
# first, and Xcode, not knowing of it, wrote the plist again over the stamp on one build and
# on another left the app signed for a plist it no longer had, which the keychain refuses.
#
# The header says the same for the same tree, and is left alone when it already says it, so
# a build with nothing new makes nothing again.
#
# DOTTO_CHANGED is yes when the working tree had uncommitted changes. An archive, which is
# what is sent out, is not made from such a tree: two different builds would carry one
# number, and neither would be the commit it names.
# Outside a git checkout nothing is known, and the number stays as the project set it.
set -e
cd "$SRCROOT/.."
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
changed=no
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then changed=yes; fi
if [ "$changed" = yes ] && [ "$ACTION" = "install" ]; then
    echo "error: there are uncommitted changes. An archive is made from a commit, which is what its build number says." >&2
    exit 1
fi
number=$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y%m%d%H%M 2>/dev/null || true)
number=${number:-$CURRENT_PROJECT_VERSION}

header="$DERIVED_FILE_DIR/Stamp.h"
says="#define DOTTO_COMMIT $commit
#define DOTTO_CHANGED $changed
#define DOTTO_BUILD $number"
mkdir -p "$DERIVED_FILE_DIR"
if [ ! -f "$header" ] || [ "$says" != "$(cat "$header")" ]; then
    printf '%s\n' "$says" > "$header"
fi
echo "stamped $commit, changed $changed, build $number"
