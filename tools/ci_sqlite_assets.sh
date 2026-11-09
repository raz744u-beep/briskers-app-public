#!/usr/bin/env bash
# Stage upstream release assets through GitHub's API on ephemeral Linux runners.
# The sqlite3 package still verifies each binary against its own pinned hash.
set -euo pipefail
version=$(awk '/^  sqlite3:$/ {found=1; next} found && /version:/ {gsub(/"/,"",$2); print $2; exit}' pubspec.lock)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
tag="sqlite3-$version"
dir=$(mktemp -d)
mkdir "$dir/$tag"
gh release download "$tag" --repo simolus3/sqlite3.dart --dir "$dir/$tag" \
  --pattern 'libsqlite3.x64.linux.so' --pattern 'libsqlite3.*.android.so'
unset GH_TOKEN
python3 - "$dir" <<'PY'
import functools
import http.server
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
serve = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), serve)
port = server.server_port
if os.fork() == 0:
    os.setsid()
    with open(os.devnull, "r+") as stream:
        for fd in (0, 1, 2):
            os.dup2(stream.fileno(), fd)
    server.serve_forever()
server.server_close()
with Path("pubspec.yaml").open("a") as spec:
    spec.write(f'\nhooks:\n  user_defines:\n    sqlite3:\n      url_pattern: "http://127.0.0.1:{port}/$RELEASE_TAG/$FILENAME"\n')
PY
