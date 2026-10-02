# Shared settings for the screen-recording scripts. Source this file; do not run it.

TOOLS_DIR=${0:A:h}
PROJECT_DIR=${TOOLS_DIR:h}
AXD=$TOOLS_DIR/bin/axd

# Everything temporary (demo files, the throwaway Chrome profile, raw captures) lives here.
WORK_DIR=${WORK_DIR:-$PROJECT_DIR/work}
# The demo folder sits at a short, impersonal path because this Finder is set to show the
# full path in the window title.
DEMO_DIR=/Users/Shared/Documents
DEMO_SRC=$PROJECT_DIR/sample-files
PROFILE_DIR=$WORK_DIR/chrome-profile
STATE_FILE=$WORK_DIR/scene-state.zsh

# --- Settings specific to the tool being demonstrated ---
TOOL_URL="https://justinpearson.github.io/easy-file-encryption/easy-file-encryption.html"
# A substring of the tool window's title, used to find that window.
TOOL_TITLE="File Encryption"
FOLDER_NAME="Tax Records"
DEMO_PASSWORD="maple-river-42"

# Screen geometry, in points. WIN is the rectangle shared by the Finder window and the browser
# window. CROP is the part of the screen that ends up in the video: WIN plus a margin of
# backdrop. It is kept clear of the top-right corner, where notifications appear.
WIN_X=160 WIN_Y=150 WIN_W=640 WIN_H=560
MARGIN=24
CROP_X=$((WIN_X - MARGIN)) CROP_Y=$((WIN_Y - MARGIN))
CROP_W=$((WIN_W + 2 * MARGIN)) CROP_H=$((WIN_H + 2 * MARGIN))
BACKDROP_COLOR="#3b4a6b"

finder_pid() { pgrep -x Finder | head -1 }

# The throwaway profile's browser process is the one Chrome process that has the profile
# path on its command line and no --type flag (renderers and helpers have one).
chrome_pid() {
	ps -axo pid=,command= | grep -F -- "--user-data-dir=$PROFILE_DIR" | grep -v -- "--type=" | grep -v grep | awk '{print $1}' | head -1
}

# Takes a screenshot of the crop region only, so nothing else on the screen is captured.
shot() {
	screencapture -x -R "$CROP_X,$CROP_Y,$CROP_W,$CROP_H" "$1"
}

# Empties the demo folder. A hidden marker file guards the delete, so a pre-existing folder at
# the same path is never touched. Finder's .DS_Store is kept because it holds the window's
# sort order.
clear_demo_dir() {
	if [[ -e ${DEMO_DIR:?} && ! -f $DEMO_DIR/.screen-demo-marker ]]; then
		print -u2 "$DEMO_DIR exists and was not created by these scripts; refusing to touch it"
		return 1
	fi
	mkdir -p $DEMO_DIR
	touch $DEMO_DIR/.screen-demo-marker
	find ${DEMO_DIR:?} -mindepth 1 -maxdepth 1 ! -name .screen-demo-marker ! -name .DS_Store -exec rm -rf {} +
}

# Recreates the demo folder holding only the sample folder.
reset_demo_dir() {
	clear_demo_dir || return 1
	cp -R "$DEMO_SRC/$FOLDER_NAME" $DEMO_DIR/
}

# Scopes that select the two demo windows.
FINDER_WIN=at:$WIN_X,$WIN_Y
CHROME_WIN="title:$TOOL_TITLE"
