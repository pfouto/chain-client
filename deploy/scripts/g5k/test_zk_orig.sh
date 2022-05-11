#!/usr/bin/env bash

# ----------------------------------- CONSTANTS -------------------------------
xmx="80G"
xms="80G"

RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ----------------------------------- PARSE PARAMS ----------------------------

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  --n_servers)
    n_servers="$2"
    shift # past argument
    shift # past value
    ;;
  *)                   # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift              # past argument
    ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -z "${n_servers}" ]]; then
  echo "n_servers not set"
  exit
fi

all_nodes=$(./nodes.sh)
start_date=$(date +"%H:%M:%S")
n_nodes=$(wc -l <<<"$all_nodes")

      if ((n_servers > n_nodes)); then
        echo -e "$RED Not enough nodes! $NC"
        exit
      fi
      mapfile -t server_nodes < <(head -n "$n_servers" <<<"$all_nodes")
      echo -e "$GREEN -- -- - Servers: $NC ${server_nodes[*]}"
      servers_without_port=""
      for snode in "${server_nodes[@]}"; do
        servers_without_port=${servers_without_port}${snode}","
      done
      servers_without_port=${servers_without_port::-1}

      echo -e "$BLUE Creating experience config file and setting nodes ids $NC"
      cp ../apache-zookeeper-chain-bin/conf/zoo_sample.cfg ../apache-zookeeper-chain-bin/conf/${OAR_JOB_ID}.cfg
      i=1
      for snode in "${server_nodes[@]}"; do
        echo "server.${i}=${snode}:2888:3888" >>../apache-zookeeper-chain-bin/conf/${OAR_JOB_ID}.cfg
        oarsh "$snode" "rm -rf /tmp/zookeeper; mkdir /tmp/zookeeper && echo ${i} > /tmp/zookeeper/myid"
        i=$((i + 1))
      done

      echo -e "$BLUE Starting servers and exiting $NC"
      unset server_p_ids
      server_p_ids=()
      for server_node in "${server_nodes[@]}"; do
        oarsh "$server_node" "cd chainpaxos/apache-zookeeper-chain-bin && \
            bin/zkServer.sh start-foreground ${OAR_JOB_ID}.cfg" 2>&1 | sed "s/^/[s-$server_node] /" &
        server_p_ids+=($!)
      done
      sleep 8

      read -p "Press any key..."

      echo "Killing servers"
      for server_node in "${server_nodes[@]}"; do
        oarsh "$server_node" "pkill java" &
      done
      for pid in "${server_p_ids[@]}"; do
        wait "$pid"
        echo -n "${pid} "
      done
      echo "Servers Killed"
