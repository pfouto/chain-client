#!/usr/bin/env bash

echo "Disabling C-States"
mapfile -t workers < <(./nodes.sh)
for worker in "${workers[@]}"; do
  oarsh "$worker" "sudo-g5k apt-get install linux-cpupower && sudo-g5k cpupower idle-set -d 3"
done