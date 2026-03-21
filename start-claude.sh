#!/bin/bash

SESSION="main"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already exists. Attaching..."
    tmux attach-session -t "$SESSION"
    exit 0
fi

# Create session with window 0 named "claude"
tmux new-session -d -s "$SESSION" -n "claude"

# Create window 1 named "monitor" and start the memory monitor
tmux new-window -t "$SESSION:1" -n "monitor"
tmux send-keys -t "$SESSION:1" "~/git/scripts/claude-monitor.sh" Enter

# Switch to window 0 (claude) and attach
tmux select-window -t "$SESSION:0"
tmux attach-session -t "$SESSION"
