#!/bin/bash
# Start APRS tracker in the shared "claude" tmux session on the canonical socket
# Called from /etc/local.d/aprs.start as user claude
#
# Socket: /tmp/tmux-shared/claude (same as tjoin everywhere)
# Session: claude
# Window: aprs

set -e
SOCK=/tmp/tmux-shared/claude
DIR=/tmp/tmux-shared

cd /home/claude/work/track_aprs

# Ensure shared dir + socket perms (same as tjoin)
mkdir -p "$DIR"
chgrp team "$DIR" 2>/dev/null || true
chmod 2770 "$DIR" 2>/dev/null || true

# Start server with detached session if not alive
if ! tmux -S "$SOCK" has-session -t claude 2>/dev/null; then
    tmux -S "$SOCK" new-session -d -s claude
fi

chgrp team "$SOCK" 2>/dev/null || true
chmod g+rw "$SOCK" 2>/dev/null || true
tmux -S "$SOCK" server-access -a smooker 2>/dev/null || true

# Kill any existing "aprs" window and re-create fresh
tmux -S "$SOCK" kill-window -t claude:aprs 2>/dev/null || true
tmux -S "$SOCK" new-window -t claude -n aprs "./track_aprs_is.sh"
