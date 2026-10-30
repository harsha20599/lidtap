#!/bin/sh
# Start LidTap and open the GUI. Creates the virtualenv on first run.
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  uv venv -q .venv && uv pip install -q --python .venv/bin/python -r requirements.txt
fi
exec .venv/bin/python -m lidtap --open "$@"
