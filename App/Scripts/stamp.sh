#!/bin/sh
# Writes into a built bundle's Info.plist the commit it was built from and when, so an app can
# say which build is running and the repository can say which build it should be. And its
# build number: the moment of that commit, to the minute, so everything built from one commit,
# an app and what is embedded in it, carries the same number, and a later commit a higher one.
#
# A "+" after the commit means the working tree had uncommitted changes at build time. An
# archive, which is what is sent out, is not made from such a tree: two different builds
# would carry one number, and neither would be the commit it names.
# Outside a git checkout nothing is known, and the number stays as the project set it.
set -e
cd "$SRCROOT/.."
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
dirty=""
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then dirty="+"; fi
if [ -n "$dirty" ] && [ "$ACTION" = "install" ]; then
    echo "error: there are uncommitted changes. An archive is made from a commit, which is what its build number says." >&2
    exit 1
fi
number=$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y%m%d%H%M 2>/dev/null || true)
when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
for key in DottoCommit DottoBuiltAt; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" 2>/dev/null || true
done
/usr/libexec/PlistBuddy -c "Add :DottoCommit string $commit$dirty" "$plist"
/usr/libexec/PlistBuddy -c "Add :DottoBuiltAt string $when" "$plist"
if [ -n "$number" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $number" "$plist"
fi
echo "stamped $commit$dirty, build ${number:-unnumbered}, at $when"
