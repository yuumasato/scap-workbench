#!/usr/bin/bash

# Copyright 2014 Red Hat Inc., Durham, North Carolina.
# All Rights Reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -u -o pipefail

trap "" SIGHUP SIGINT SIGTERM

# pkexec writes a message to stderr when user dismisses it, we always skip 1 line.
# if user did not dismiss it we should print a dummy line to stderr so that nothing
# valuable gets skipped
echo "Dummy text" 1>&2

wrapper_uid=$1
shift
wrapper_gid=$1
shift

TEMP_DIR=`mktemp -d`

args=("$@")

# We have to rewrite result targets to a priv temp dir. We will later
# chown that dir to the target uid:gid and copy things where they belong
# using permissions of that user ONLY!
for i in $(seq 0 `expr $# - 1`); do
    let j=i+1

    case "${args[i]}" in
    ("--results")
        TARGET_RESULTS_XCCDF=${args[j]}
        args[j]="$TEMP_DIR/results-xccdf.xml"
      ;;
    ("--results-arf")
        TARGET_RESULTS_ARF=${args[j]}
        args[j]="$TEMP_DIR/results-arf.xml"
      ;;
    ("--report")
        TARGET_REPORT=${args[j]}
        args[j]="$TEMP_DIR/report.html"
      ;;
    *)
      ;;
    esac
done

LOCAL_OSCAP="oscap"

pushd "$TEMP_DIR" > /dev/null
$LOCAL_OSCAP ${args[@]} &
PID=$!
RET=1

while kill -0 $PID 2> /dev/null; do
    # we don't even care what we read, we just read until stdin is closed
    if ! read dummy; then
        echo "KILLL $PID"
        kill -s SIGINT $PID 2> /dev/null
        break
    fi

    # The protocol sends communication every 1 second
    sleep 0.5
done

wait $PID
RET=$?

popd > /dev/null

chown -R $wrapper_uid:$wrapper_gid "$TEMP_DIR"

[ -f $TEMP_DIR/results-xccdf.xml ] || sudo -u \#$wrapper_uid -g \#$wrapper_gid cp "$TEMP_DIR/results-xccdf.xml" $TARGET_RESULTS_XCCDF
[ -f $TEMP_DIR/results-arf.xml ] || sudo -u \#$wrapper_uid -g \#$wrapper_gid cp "$TEMP_DIR/results-arf.xml" $TARGET_RESULTS_ARF
[ -f $TEMP_DIR/report.html ] || sudo -u \#$wrapper_uid -g \#$wrapper_gid cp "$TEMP_DIR/report.html" $TARGET_REPORT

rm -r "$TEMP_DIR"

exit $RET
