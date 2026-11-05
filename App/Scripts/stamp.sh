#!/bin/sh
# Writes the commit an app was built from, and when, into its Info.plist, so the app can say
# which build is running and the repository can say which build it should be. A "+" after
# the commit means the working tree had uncommitted changes at build time.
set -e
cd "$SRCROOT/.."
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then commit="$commit+"; fi
when=$(date -u +%Y-%m-%dT%H:%M:%SZ)
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
for key in MarginCommit MarginBuiltAt; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" 2>/dev/null || true
done
/usr/libexec/PlistBuddy -c "Add :MarginCommit string $commit" "$plist"
/usr/libexec/PlistBuddy -c "Add :MarginBuiltAt string $when" "$plist"
echo "stamped $commit at $when"
