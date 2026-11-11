#!/usr/bin/env bash
# Installs what a CI job needs from the runner's own package mirror, trying again when the
# network fails. Run 43034260707 and 43034270040 failed before any check ran: a download
# of Lua timed out, and security.ubuntu.com could not be resolved. Those are not test
# failures, and retrying is how they are told apart: a package that still cannot be
# installed after every try fails the job, so a check is never skipped and called green.
#
#     tools/ci/install_lua.sh lua5.1          # luac5.1, for the syntax check
#     tools/ci/install_lua.sh lua5.4          # lua, for the tests
#     tools/ci/install_lua.sh lua-check       # luacheck
set -euo pipefail

TRIES=5
for try in $(seq 1 "$TRIES"); do
    if sudo apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 update -q \
        && sudo apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 install -y -q --no-install-recommends "$@"; then
        echo "installed: $* (try $try)"
        exit 0
    fi
    echo "install of $* failed (try $try of $TRIES); waiting before the next" >&2
    sleep $((try * 15))
done
echo "could not install $* after $TRIES tries" >&2
exit 1
