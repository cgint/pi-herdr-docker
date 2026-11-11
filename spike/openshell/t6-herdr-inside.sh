#!/usr/bin/env bash
# T6 (inside the sandbox): herdr server is the canonical main process; drive it over its
# socket API: create a workspace, split a pane, start two pi panes, prompt one.
set -uo pipefail
export PATH=/usr/local/share/npm-global/bin:$PATH
PIC='export PATH=/usr/local/share/npm-global/bin:$PATH; pi --provider home-llm --model glm-5.3-flash-direct'
herdr status server
ws=$(herdr workspace create --cwd /sandbox --label os-spike --no-focus)
echo "workspace: $ws"
herdr pane list
