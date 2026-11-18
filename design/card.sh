#!/bin/sh
# The picture a link to dotto.works shows where it is pasted: design/card.html, 1200 by
# 630, taken by a headless Chrome into site/card.png at twice that, 2400 by 1260, so its
# words stay sharp on a phone's screen and after an app has made it smaller. Run it when
# the card changes:
#
#     design/card.sh
#
# CHROME names the browser when it is not where a Mac keeps it.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
profile=$(mktemp -d)
trap 'rm -rf "$profile"' EXIT

"$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$profile" \
    --force-device-scale-factor=2 --window-size=1200,630 --virtual-time-budget=2000 \
    --screenshot="$here/../site/card.png" "file://$here/card.html" >/dev/null 2>&1
echo "site/card.png  $(wc -c < "$here/../site/card.png" | tr -d ' ') bytes"
