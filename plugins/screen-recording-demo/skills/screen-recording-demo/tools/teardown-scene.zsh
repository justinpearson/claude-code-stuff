#!/bin/zsh
# Undoes tools/setup-scene.zsh: restores the Finder bars that were hidden for the recording,
# closes the demo Finder window, quits the throwaway Chrome instance, restores the save
# dialog's expanded state, and removes the demo folder.
#
# Usage: tools/teardown-scene.zsh

source ${0:A:h}/common.zsh

FPID=$(finder_pid)
CPID=$(chrome_pid)
typeset -a RESTORE
ORIG_OPEN_SIZE= ORIG_SAVE_EXPANDED=
[[ -f $STATE_FILE ]] && source $STATE_FILE

if $AXD find $FPID $FINDER_WIN role=AXWindow >/dev/null 2>&1; then
	$AXD raise $FPID $FINDER_WIN >/dev/null
	sleep 0.6
	for item in $RESTORE; do
		$AXD menu $FPID press View $item >/dev/null && print "Finder: $item"
		sleep 0.4
	done
	$AXD press $FPID $FINDER_WIN subrole=AXCloseButton >/dev/null
	sleep 0.5
fi
if [[ -n $CPID ]]; then
	kill $CPID
	sleep 1.5
fi

# A take collapses Chrome's save dialog and resizes its open dialog, and those settings are
# shared with the everyday Chrome profile, so put back the values recorded at setup.
[[ -n $ORIG_OPEN_SIZE ]] && defaults write com.google.Chrome NSNavPanelExpandedSizeForOpenMode -string $ORIG_OPEN_SIZE
[[ $ORIG_SAVE_EXPANDED == 1 ]] && defaults write com.google.Chrome NSNavPanelExpandedStateForSaveMode -bool true

if [[ -f ${DEMO_DIR:?}/.screen-demo-marker ]]; then
	clear_demo_dir
	rm -f $DEMO_DIR/.screen-demo-marker $DEMO_DIR/.DS_Store
	rmdir $DEMO_DIR && print "removed $DEMO_DIR"
fi

rm -f $STATE_FILE
open -a Terminal
