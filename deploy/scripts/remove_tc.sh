#!/usr/bin/env bash

INTERFACE="br0"
V_INTERFACE="ifb0"

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'

allnodes=`./nodes.sh`
echo -e $GREEN-------------------------------- Remove outgoing limit...$NC
cmd1="sudo-g5k tc qdisc del root dev ${INTERFACE}"
echo -e " -- $cmd1"

for node in $allnodes; do
    oarsh $node "$cmd1" &
done

wait

echo -e $GREEN-------------------------------- Remove incoming limit...$NC
for node in $allnodes; do
    echo -e ${BLUE}${node}${NC}
    cmd1="sudo-g5k tc qdisc del dev ${INTERFACE} handle ffff: ingress"
    cmd4="sudo-g5k tc qdisc del root dev ${V_INTERFACE}"
    echo -e " -- $cmd1"
    oarsh $node "$cmd1"
    echo -e " -- $cmd4"
    oarsh $node "$cmd4"
done
wait

echo -e $GREEN-------------------------------- Removing ifb...$NC
for node in $allnodes; do
    echo -e ${BLUE}${node}${NC}
    cmd2="sudo-g5k ip link set dev ${V_INTERFACE} down"
    echo -e " -- $cmd2"
    oarsh $node "$cmd2"
done
wait


echo -e "$GREEN------------- Done$NC"
