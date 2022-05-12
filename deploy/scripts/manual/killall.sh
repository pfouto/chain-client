#!/bin/bash

cmd=$1
nodes=`./nodes.sh`

for node in $nodes
do
	#echo $node
        ssh -o "StrictHostKeyChecking no" $node "killall java" 2>&1 | sed "s/^/[$node] /"
done
echo done!