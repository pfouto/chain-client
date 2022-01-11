#!/usr/bin/env bash
if [[ -z "$1" ]]
then
	echo "Usage: setupdelay.sh [nservers]"
	exit
fi

RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'

nservers=$1

allnodes=`./nodes.sh`
declare -a servernodes
declare -a clientnodes

requirednodes=$(($nservers))
idx=0
for i in $allnodes; do
	if [ $idx -eq $requirednodes ]; then
		echo "breaking early at $idx"
		break;
	fi
	if (( $idx < $nservers ))
	then
		servernodes+=($i)
		lastserver=($i)
		echo "----- Server: $i"
	else
		clientnodes+=($i)
		echo " --------- $i"
	fi
	idx=$((idx+1))
done
echo "idx $idx"
echo "required $requirednodes"
if [ $idx -lt $requirednodes ]; then
	echo "Not enough nodes"
	exit
fi

echo -e $GREEN"Servers: "$NC${servernodes[@]}

declare -A latencymap

latencymap[0,0]=-1
latencymap[0,1]=46
latencymap[0,2]=63
latencymap[0,3]=102
latencymap[0,4]=93
latencymap[1,0]=44
latencymap[1,1]=-1
latencymap[1,2]=105
latencymap[1,3]=144
latencymap[1,4]=139
latencymap[2,0]=61
latencymap[2,1]=103
latencymap[2,2]=-1
latencymap[2,3]=169
latencymap[2,4]=179
latencymap[3,0]=105
latencymap[3,1]=146
latencymap[3,2]=162
latencymap[3,3]=-1
latencymap[3,4]=80
latencymap[4,0]=94
latencymap[4,1]=143
latencymap[4,2]=154
latencymap[4,3]=78
latencymap[4,4]=-1

echo Setting up TC...

cmd1="sudo-g5k sudo ip link set eno2 down"

for ((i=0;i<$(($nservers));i++)) do
	echo "${servernodes[$i]} -- $cmd1"
	oarsh ${servernodes[$i]} "$cmd1"
done
wait
sleep 5

for ((i=0;i<$(($nservers));i++)) do
	cmd="sudo-g5k tc qdisc del dev br0 root"
	echo "${servernodes[$i]} -- $cmd"
  oarsh ${servernodes[$i]} "$cmd" &
done
wait

for ((i=0;i<$(($nservers));i++)) do
	cmd="sudo-g5k tc qdisc add dev br0 root handle 1: htb"
	echo "${servernodes[$i]} -- $cmd"
	oarsh ${servernodes[$i]} "$cmd"
  for ((j=0;j<$nservers;j++)) do
		if [ $i -eq $j ]; then
			continue
		fi

		targetip=$(getent hosts ${servernodes[$j]} | awk '{print $1}')
		echo "latency from ${servernodes[$i]} to ${servernodes[$j]} ($targetip) is ${latencymap[$i,$j]}"
		cmd="sudo-g5k tc class add dev br0 parent 1: classid 1:$(($j+1))1 htb rate 1000mbit"
    echo "-- ${servernodes[$i]} ------- $cmd"
    oarsh ${servernodes[$i]} "$cmd"

		cmd="sudo-g5k tc qdisc add dev br0 parent 1:$(($j+1))1 handle $(($j+1))10: netem delay ${latencymap[$i,$j]}ms $((${latencymap[$i,$j]}*3/100))ms distribution normal"
    echo "-- ${servernodes[$i]} ------- $cmd"
    oarsh ${servernodes[$i]} "$cmd"

		cmd="sudo-g5k tc filter add dev br0 protocol ip parent 1:0 prio 1 u32 match ip dst $targetip flowid 1:$(($j+1))1"
		echo " -- ${servernodes[$i]} ------ $cmd"
    oarsh ${servernodes[$i]} "$cmd"
  done
done