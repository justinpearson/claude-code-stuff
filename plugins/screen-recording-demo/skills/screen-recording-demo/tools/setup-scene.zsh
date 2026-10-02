#!/bin/zsh
# Builds the recording scene: a solid backdrop window, a browser window showing the tool, and a
# Finder window showing the demo folder, the last two stacked on the same rectangle.
# The browser is a separate Chrome instance with a throwaway profile, so no bookmarks,
# extensions, history, or account details can appear in the recording.
#
# Usage: tools/setup-scene.zsh            (undo with tools/teardown-scene.zsh)

set -e
source ${0:A:h}/common.zsh

mkdir -p $WORK_DIR
reset_demo_dir

# --- Browser: backdrop first, then the tool window on top of it -------------------------
CHROME_FLAGS=(
	--user-data-dir=$PROFILE_DIR
	--no-first-run
	--no-default-browser-check
	--use-mock-keychain
	--disable-search-engine-choice-screen
	--force-renderer-accessibility
)
if [[ -z $(chrome_pid) ]]; then
	open -na "Google Chrome" --args $CHROME_FLAGS \
		--app="data:text/html,<title>Backdrop</title><body style='background:${BACKDROP_COLOR/\#/%23}'>"
	for i in {1..50}; do [[ -n $(chrome_pid) ]] && break; sleep 0.2; done
	sleep 2
	open -na "Google Chrome" --args $CHROME_FLAGS --app=$TOOL_URL
	sleep 3
fi
CPID=$(chrome_pid)
[[ -n $CPID ]] || { print -u2 "demo Chrome did not start"; exit 1 }

$AXD setframe $CPID title:Backdrop $((CROP_X - 60)) $((CROP_Y - 60)) $((CROP_W + 120)) $((CROP_H + 120))
$AXD setframe $CPID $CHROME_WIN $WIN_X $WIN_Y $WIN_W $WIN_H

# --- Finder window on the demo folder ---------------------------------------------------
FPID=$(finder_pid)
if ! $AXD find $FPID $FINDER_WIN role=AXWindow >/dev/null 2>&1; then
	open $DEMO_DIR
	sleep 1.5
	$AXD setframe $FPID title:$DEMO_DIR $WIN_X $WIN_Y $WIN_W $WIN_H
fi

# The sidebar lists personal folders and machine names, the path bar shows the disk name, and
# the status bar shows free disk space, so all three are hidden for the recording. What was
# visible beforehand is written to the state file so teardown can restore it, along with the
# file-dialog settings that a take changes and that are shared with the everyday Chrome.
if [[ ! -f $STATE_FILE ]]; then
	view_menu=$($AXD menu $FPID list View)
	print "ORIG_OPEN_SIZE=\"$(defaults read com.google.Chrome NSNavPanelExpandedSizeForOpenMode 2>/dev/null)\"" > $STATE_FILE
	print "ORIG_SAVE_EXPANDED=\"$(defaults read com.google.Chrome NSNavPanelExpandedStateForSaveMode 2>/dev/null)\"" >> $STATE_FILE
	for bar in Sidebar "Path Bar" "Status Bar"; do
		if print $view_menu | grep -q "^Hide $bar"; then
			print "RESTORE+=(\"Show $bar\")" >> $STATE_FILE
			$AXD menu $FPID press View "Hide $bar"
			sleep 0.4
		fi
	done
	$AXD setframe $FPID $FINDER_WIN $WIN_X $WIN_Y $WIN_W $WIN_H
fi
# Icons sorted by name sit on a grid, so new files appear beside the folder, not on top of it.
$AXD menu $FPID press View "Sort By" Name >/dev/null

# --- Stacking order ---------------------------------------------------------------------
# Opening the folder brought every Finder window forward. Lift the backdrop, the tool window,
# and the demo Finder window above them, one at a time and in that order.
$AXD raise $CPID title:Backdrop
sleep 0.5
$AXD raise $CPID $CHROME_WIN
sleep 0.4
$AXD raise $FPID $FINDER_WIN
sleep 0.6

print "chrome pid $CPID, finder pid $FPID"
$AXD zorder | grep "layer=0" | head -4
