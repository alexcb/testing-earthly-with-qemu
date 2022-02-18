#!/bin/sh
set -e

# check for cgroupv2
ls /sys/fs/cgroup/cgroup.subtree_control || (echo cgroups v2 not found && exit 1)


grp="testgrp"
grppath="/sys/fs/cgroup/$grp"

if [ ! -d "$grppath" ]; then
  mkdir "$grppath"
fi

echo "to view what controllers are available, run: cat $grppath/cgroup.controllers"
cat "$grppath/cgroup.controllers"

echo "to view what controllers are enabled, run: cat $grppath/cgroup.subtree_control"
cat "$grppath/cgroup.subtree_control"

/bin/sh -c 'while true; do echo -n hello && date; sleep 1; done' &
shproc="$!"
echo "moving proc $shproc to $grp"

echo "$shproc" > "$grppath/cgroup.procs"

echo "to view current procs in $grp, run: cat /sys/fs/cgroup/testgrp/cgroup.procs"
cat /sys/fs/cgroup/testgrp/cgroup.procs

# NOTES
# cgroup controllers can only be exclusively used in a single cgroup version;
# for this reason, it's probably best to migrate to cgroup v2 and disable cgroup v1 with cgroup_no_v1=all

# otherwise, if a controller is missing, then it's not enabled in the parent.

# other controllers such as freeze are always availabled, and are ommitted from the cgroup.controllers file.
# controllers must be enabled (i.e. added to cgroup.subtree_control) in order for children to see them in cgroup.controllers

