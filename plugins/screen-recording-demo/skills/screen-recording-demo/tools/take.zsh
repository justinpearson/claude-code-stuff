#!/bin/zsh
# Records one take of the tutorial: drives Finder and the browser with the real cursor while
# ffmpeg captures the crop region of the screen.
#
# Usage: tools/take.zsh encrypt|decrypt [--dry-run]
#
# Output: work/raw-<name>.mkv (frames stamped with system uptime) and work/<name>.log (the
# driver's actions and step marks on the same clock). tools/render.py turns the pair into the
# finished video. --dry-run performs the actions without recording.
#
# The scene must already be built with tools/setup-scene.zsh. Keep hands off the mouse and
# keyboard while a take runs.

set -e
source ${0:A:h}/common.zsh

NAME=$1
[[ $NAME == encrypt || $NAME == decrypt ]] || { print -u2 "usage: take.zsh encrypt|decrypt [--dry-run]"; exit 1 }
DRY_RUN=0
[[ $2 == --dry-run ]] && DRY_RUN=1

CPID=$(chrome_pid)
FPID=$(finder_pid)
[[ -n $CPID ]] || { print -u2 "demo Chrome is not running; run tools/setup-scene.zsh"; exit 1 }

RAW=$WORK_DIR/raw-$NAME.mkv
LOG=$WORK_DIR/$NAME.log
ENC_COPY="$WORK_DIR/$FOLDER_NAME.zip.enc"

# Sheet sizes that fit inside the crop region.
SHEET_W=675 OPEN_SHEET_H=320

ax() { $AXD "$@" }
finder() { local cmd=$1; shift; ax $cmd $FPID $FINDER_WIN "$@" }
chrome() { local cmd=$1; shift; ax $cmd $CPID $CHROME_WIN "$@" }
mark() { ax mark "$@" }
pause() { sleep $1 }

# --- Staging (not recorded) -------------------------------------------------------------

# Puts the demo Finder window on the demo folder itself, not a subfolder.
finder_to_demo_dir() {
	ax raise $FPID $FINDER_WIN >/dev/null
	pause 0.4
	local tries=0
	while [[ $(ax title $FPID $FINDER_WIN) != $DEMO_DIR ]]; do
		(( ++tries > 3 )) && { print -u2 "could not navigate Finder to $DEMO_DIR"; exit 1 }
		ax key cmd+up
		pause 0.8
	done
}

reload_tool() {
	ax raise $CPID $CHROME_WIN >/dev/null
	pause 0.4
	ax key cmd+r
	pause 1.5
	chrome wait 5 id=action "title=Choose a file" >/dev/null
}

# Restacks the three demo windows with `front` ("finder" or "chrome") on top.
stack() {
	ax raise $CPID title:Backdrop >/dev/null
	pause 0.4
	if [[ $1 == finder ]]; then
		ax raise $CPID $CHROME_WIN >/dev/null; pause 0.4
		ax raise $FPID $FINDER_WIN >/dev/null
	else
		ax raise $FPID $FINDER_WIN >/dev/null; pause 0.4
		ax raise $CPID $CHROME_WIN >/dev/null
	fi
	pause 0.6
}

park_cursor() { ax move $((WIN_X + $1)) $((WIN_Y + $2)) 200 }

# --- Shared steps -----------------------------------------------------------------------

# The file dialog opens wider than the crop region, and its size setting does not persist
# between uses, so it is shrunk as soon as it appears. The frames between the click and the
# settled dialog are bracketed with cut marks and removed when the video is rendered.
choose_file() {
	chrome moveto id=file-input dx=-150
	pause 0.2
	ax click
	mark cut-start
	chrome wait 5 role=AXSheet >/dev/null
	for i in {1..10}; do
		chrome setsize $SHEET_W $OPEN_SHEET_H role=AXSheet >/dev/null
		pause 0.15
		[[ $(chrome find role=AXSheet | awk '{print $5}') == $SHEET_W ]] && break
	done
	chrome wait 5 role=AXTextField "value=$1" >/dev/null
	pause 0.5
	mark cut-end
	pause 0.4
	chrome moveto role=AXTextField "value=$1"
	pause 0.15
	ax click
	pause 0.35
	chrome moveto role=AXButton title=Open
	pause 0.15
	ax click
	chrome gone 5 role=AXSheet
	pause 0.5
}

type_password() {
	chrome moveto id=password-input
	pause 0.15
	ax click
	pause 0.25
	ax type $DEMO_PASSWORD 70
	pause 0.45
}

# Clicks Encrypt or Decrypt, then Save in the dialog that follows. The dialog is collapsed to
# its compact form if it opens expanded, because the expanded form lists personal folders.
run_and_save() {
	chrome moveto id=action
	pause 0.2
	ax click
	mark cut-start
	chrome wait 5 role=AXSheet >/dev/null
	pause 0.3
	if chrome find id=NS_OPEN_SAVE_DISCLOSURE_TRIANGLE value=1 >/dev/null 2>&1; then
		chrome press id=NS_OPEN_SAVE_DISCLOSURE_TRIANGLE >/dev/null
		pause 0.8
	fi
	chrome find role=AXPopUpButton "value=${DEMO_DIR:t}" >/dev/null 2>&1 \
		|| { print -u2 "save dialog is not pointed at the demo folder"; exit 1 }
	pause 0.5
	mark cut-end
	pause 0.7
	chrome moveto role=AXButton title=Save
	pause 0.2
	ax click
	chrome gone 5 role=AXSheet
	# Chrome shows a stray "No file chosen" tooltip about a second after the dialog closes.
	# A key press while the tooltip is pending cancels it.
	pause 0.25
	ax key escape
	chrome moveto id=status dx=-60 &
	local move_pid=$!
	pause 0.35
	ax key escape
	wait $move_pid
	pause 1.3
}

# --- Takes ------------------------------------------------------------------------------

stage_encrypt() {
	finder_to_demo_dir
	reset_demo_dir
	pause 1
	reload_tool
	stack finder
	# Start inside the folder, so the video opens on the files that are about to be encrypted.
	finder moveto role=AXImage "title=$FOLDER_NAME"
	ax dclick
	finder wait 5 role=AXImage "title=Receipts.pdf" >/dev/null
	park_cursor 430 330
	pause 1
}

run_encrypt() {
	mark step 1
	pause 1.4
	finder moveto desc=back
	pause 0.15
	ax click
	finder wait 5 role=AXImage "title=$FOLDER_NAME" >/dev/null
	pause 0.5

	mark step 2
	finder moveto role=AXImage "title=$FOLDER_NAME"
	pause 0.2
	ax rclick
	# The context menu hangs off the clicked icon in the accessibility tree, so searching the
	# demo window finds it quickly; searching the whole app walks every open Finder window.
	finder wait 5 role=AXMenuItem "title~Compress" >/dev/null
	pause 0.6
	finder moveto role=AXMenuItem "title~Compress"
	pause 0.3
	ax click
	finder wait 10 role=AXImage "title=$FOLDER_NAME.zip" >/dev/null
	pause 1.2

	mark step 3
	ax raise $CPID $CHROME_WIN >/dev/null
	pause 0.6
	choose_file "$FOLDER_NAME.zip"

	mark step 4
	type_password

	mark step 5
	run_and_save

	mark step 6
	ax raise $FPID $FINDER_WIN >/dev/null
	finder wait 5 role=AXImage "title=$FOLDER_NAME.zip.enc" >/dev/null
	pause 0.4
	finder moveto role=AXImage "title=$FOLDER_NAME.zip.enc"
	pause 0.15
	ax click
	pause 2.2
	mark end
}

stage_decrypt() {
	[[ -f $ENC_COPY ]] || { print -u2 "no encrypted file from an encrypt take at $ENC_COPY"; exit 1 }
	finder_to_demo_dir
	clear_demo_dir
	cp $ENC_COPY $DEMO_DIR/
	pause 1
	reload_tool
	stack chrome
	park_cursor 500 120
	pause 1
}

run_decrypt() {
	mark step 1
	pause 0.7
	choose_file "$FOLDER_NAME.zip.enc"

	mark step 2
	type_password

	mark step 3
	run_and_save

	mark step 4
	ax raise $FPID $FINDER_WIN >/dev/null
	finder wait 5 role=AXImage "title=$FOLDER_NAME.zip" >/dev/null
	pause 0.5
	finder moveto role=AXImage "title=$FOLDER_NAME.zip"
	pause 0.2
	ax dclick
	finder wait 10 role=AXImage "title=$FOLDER_NAME" >/dev/null
	pause 1.1

	mark step 5
	finder moveto role=AXImage "title=$FOLDER_NAME"
	pause 0.2
	ax dclick
	finder wait 5 role=AXImage "title=Receipts.pdf" >/dev/null
	park_cursor 430 330
	pause 2.2
	mark end
}

# --- Recording --------------------------------------------------------------------------

FFMPEG_PID=
stop_recording() {
	[[ -n $FFMPEG_PID ]] || return 0
	kill -INT $FFMPEG_PID 2>/dev/null || true
	wait $FFMPEG_PID 2>/dev/null || true
	FFMPEG_PID=
}
trap stop_recording EXIT

start_recording() {
	rm -f $RAW
	# The crop happens at capture time, so the raw file never contains the rest of the screen.
	# -copyts keeps the capture's uptime-based timestamps, which match the driver's log.
	ffmpeg -hide_banner -loglevel error -y \
		-f avfoundation -framerate 30 -capture_cursor 1 -capture_mouse_clicks 1 -pixel_format nv12 \
		-i "Capture screen 0:none" -copyts \
		-vf "crop=$((CROP_W * 2)):$((CROP_H * 2)):$((CROP_X * 2)):$((CROP_Y * 2))" \
		-c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv420p $RAW 2>$WORK_DIR/ffmpeg-$NAME.err &
	FFMPEG_PID=$!
	for i in {1..50}; do [[ -s $RAW ]] && break; sleep 0.1; done
	sleep 0.8
}

stage_$NAME
rm -f $LOG
export AXD_LOG=$LOG
(( DRY_RUN )) || start_recording
run_$NAME
sleep 0.4
stop_recording
unset AXD_LOG

[[ $NAME == encrypt ]] && cp "$DEMO_DIR/$FOLDER_NAME.zip.enc" $ENC_COPY
print "take '$NAME' finished"
(( DRY_RUN )) || ls -la $RAW
grep -c . $LOG
