#!/bin/bash
nodes=$(uniq "hosts")

for n in $nodes
do
	echo "$n"
done
