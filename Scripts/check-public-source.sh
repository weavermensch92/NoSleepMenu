#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Scan tracked source only: build caches and Git metadata contain local machine paths.
python3 - <<'PY'
import re, subprocess, sys
from pathlib import Path
patterns = [r'/' + r'Users/[^/\s"\']+', r'(?<![\w.])(?:10|192\.168)\.\d+\.\d+(?:\.\d+)?', r'gh[pousr]_[A-Za-z0-9]{25,}', r'sk-(?:ant-)?[A-Za-z0-9_-]{20,}', r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----']
files = subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
failed = []
for name in filter(None, files):
    path = Path(name)
    if not path.is_file(): continue
    try: text = path.read_text()
    except UnicodeDecodeError: continue
    for pattern in patterns:
        if re.search(pattern,text): failed.append(name); break
if failed:
    print('Review potentially private material in: ' + ', '.join(sorted(set(failed))))
    sys.exit(1)
print('Public-source privacy scan passed.')
PY
