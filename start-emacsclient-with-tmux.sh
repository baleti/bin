#!/usr/bin/env sh

#!/bin/bash
# Auto-start tmux if not already running in a tmux session
if [ -z "$TMUX" ]; then
  # Create a unique session name based on the terminal process ID
  SESSION_NAME="auto-$(basename "$SHELL")-$$"
  # Check if a tmux session with this name already exists
  tmux has-session -t "$SESSION_NAME" 2>/dev/null
  if [ $? != 0 ]; then
    # If the session does not exist, create a new one and run emacsclient
    tmux new-session -s "$SESSION_NAME" "emacsclient -t"
  else
    # If it exists, attach to the existing session and run emacsclient in new window
    tmux attach-session -t "$SESSION_NAME" \; new-window "emacsclient -t"
  fi
else
  # Already in tmux, just run emacsclient
  emacsclient -t
fi
