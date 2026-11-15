#!/bin/sh
# Makes the copy that goes out: this commit's tree, without what .gitattributes marks
# export-ignore, as one new commit in a repository of its own.
#
#     App/Scripts/publish.sh ../dotto
#
# The work stays here, with its history, whose messages quote the owner's notebook. What
# goes out has one commit a release and says only which version it is. The destination is
# made on the first run; after that it must be the repository this script made, since
# everything in it but its history is replaced. Nothing is pushed: that is done by hand,
# from the destination.
set -e
dest=${1:?usage: publish.sh <folder of the public repository>}
cd "$(git rev-parse --show-toplevel)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "error: there are uncommitted changes. What goes out is a commit." >&2
    exit 1
fi
commit=$(git rev-parse --short HEAD)
version=$(sed -n 's/^MARKETING_VERSION = //p' App/Config/Base.xcconfig)

if [ -e "$dest" ] && [ ! -f "$dest/.dotto-public" ]; then
    echo "error: $dest exists and was not made by this script." >&2
    exit 1
fi
mkdir -p "$dest"
dest=$(cd "$dest" && pwd)
[ -d "$dest/.git" ] || git -C "$dest" init -q -b main

# Out with the last release's files, in with this commit's.
find "$dest" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git archive --format=tar HEAD | tar -x -C "$dest"
# The mark this script knows its own folder by. It is not part of what goes out.
: > "$dest/.dotto-public"
grep -qxF ".dotto-public" "$dest/.git/info/exclude" 2>/dev/null || echo ".dotto-public" >> "$dest/.git/info/exclude"

git -C "$dest" add -A
if git -C "$dest" diff --cached --quiet; then
    echo "nothing new to publish: $dest already holds $commit"
    exit 0
fi
git -C "$dest" commit -q -m "Dotto $version"
echo "published $commit as Dotto $version in $dest: $(git -C "$dest" rev-parse --short HEAD)"
