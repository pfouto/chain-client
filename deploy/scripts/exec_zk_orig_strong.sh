#!/usr/bin/env bash

# ----------------------------------- CONSTANTS -------------------------------
xmx="80G"
xms="80G"

RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ----------------------------------- PARSE PARAMS ----------------------------
zoo_url="localhost"
start_run=1

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  --exp_name)
    exp_name="$2"
    shift # past argument
    shift # past value
    ;;
  --n_clients)
    n_clients="$2"
    shift # past argument
    shift # past value
    ;;
  --n_runs)
    n_runs="$2"
    shift # past argument
    shift # past value
    ;;
  --start_run)
    start_run="$2"
    shift # past argument
    shift # past value
    ;;
  --payloads)
    payloads_arg="$2"
    shift # past argument
    shift # past value
    ;;
  --n_servers)
    n_servers_arg="$2"
    shift # past argument
    shift # past value
    ;;
  --reads_per)
    reads_arg="$2"
    shift # past argument
    shift # past value
    ;;
  --n_threads)
    n_threads_arg="$2"
    shift # past argument
    shift # past value
    ;;
  --zoo_url)
    zoo_url="$2"
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

if [[ -z "${exp_name}" ]]; then
  echo "exp_name not set"
  exit
fi
if [[ -z "${n_clients}" ]]; then
  echo "n_clients not set"
  exit
fi
if [[ -z "${n_runs}" ]]; then
  echo "n_runs not set"
  exit
fi
if [[ -z "${payloads_arg}" ]]; then
  echo "payloads not set"
  exit
fi
if [[ -z "${n_servers_arg}" ]]; then
  echo "n_servers not set"
  exit
fi
if [[ -z "${reads_arg}" ]]; then
  echo "reads_per not set"
  exit
fi
if [[ -z "${n_threads_arg}" ]]; then
  echo "n_threads not set"
  exit
fi

all_nodes=$(./nodes.sh)
start_date=$(date +"%H:%M:%S")
n_nodes=$(wc -l <<<"$all_nodes")

mapfile -t client_nodes < <(tail -n "$n_clients" <<<"$all_nodes")
IFS=', ' read -r -a payloads_list <<<"$payloads_arg"
IFS=', ' read -r -a n_servers_list <<<"$n_servers_arg"
IFS=', ' read -r -a reads_list <<<"$reads_arg"
IFS=', ' read -r -a threads_list <<<"$n_threads_arg"

total_runs=$((n_runs * ${#payloads_list[@]} * ${#n_servers_list[@]} * ${#reads_list[@]} * ${#threads_list[@]}))

# ----------------------------------- LOG PARAMS ------------------------------
echo -e "$BLUE\n ---- CONFIG ----  $NC"
echo -e "$GREEN exp_name: $NC \t\t\t${exp_name}"
echo -e "$GREEN clients (${n_clients}): $NC \t\t\t${client_nodes[*]}"
echo -e "$GREEN n_runs: $NC	\t\t${n_runs}"
echo -e "$GREEN start_run: $NC \t\t\t${start_run}"
echo -e "$GREEN n_servers: $NC \t\t\t${n_servers_list[*]}"
echo -e "$GREEN reads_percent: $NC \t\t${reads_list[*]}"
echo -e "$GREEN payloads: $NC \t\t\t${payloads_list[*]}"
echo -e "$GREEN n threads: $NC \t\t\t${threads_list[*]}"
echo -e "$GREEN ---------- $NC"
echo -e "$GREEN number of runs: $NC \t\t${total_runs}"
echo -e "$BLUE ---- END CONFIG ---- \n $NC"

current_run=0

# ----------------------------------- START EXP -------------------------------

for run in $(# ------------------------------------------- RUN
  seq "$start_run" $((n_runs + start_run - 1))
); do
  echo -e "$GREEN -- STARTING RUN  $NC$run"
  for payload in "${payloads_list[@]}"; do # ------------------------- PAYLOADS
    echo -e "$GREEN -- -- -- -- STARTING PAYLOAD $NC$payload"

    for n_servers in "${n_servers_list[@]}"; do # --------------------------- N_SERVERS
      echo -e "$GREEN -- -- STARTING N_SERVERS $NC$n_servers"
      if ((n_clients + n_servers > n_nodes)); then
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
      cp ../apache-zookeeper-3.7.0-bin/conf/zoo_sample.cfg ../apache-zookeeper-3.7.0-bin/conf/${OAR_JOB_ID}.cfg
      i=1
      for snode in "${server_nodes[@]}"; do
        echo "server.${i}=${snode}:2888:3888" >>../apache-zookeeper-3.7.0-bin/conf/${OAR_JOB_ID}.cfg
        oarsh "$snode" "rm -rf /tmp/zookeeper; mkdir /tmp/zookeeper && echo ${i} > /tmp/zookeeper/myid"
        i=$((i + 1))
      done

      echo -e "$BLUE Starting servers and sleeping 8 for LOADING $NC"
      unset server_p_ids
      server_p_ids=()
      for server_node in "${server_nodes[@]}"; do
        oarsh "$server_node" "cd chainpaxos/apache-zookeeper-3.7.0-bin && \
            bin/zkServer.sh start-foreground ${OAR_JOB_ID}.cfg" 2>&1 | sed "s/^/[s-$server_node] /" &
        server_p_ids+=($!)
      done
      sleep 8
      echo -e "$BLUE Loading data $NC"
      oarsh "${client_nodes[0]}" "cd chainpaxos/client && java -cp chain-client.jar:. \
                          site.ycsb.Client -t -s -P config.properties -load \
                          -p db=ZKClient -p hosts=${server_nodes[0]} \
                          -p zookeeper.syncRead=true \
    											-threads 50 -p fieldlength=$payload \
    											| tee /dev/null" |& sed "s/^/[c-${client_nodes[0]}] /" &
      lpid=($!)
      wait "$lpid"
      echo -e "$BLUE Loading done! $NC"

      echo "Killing servers"
      for server_node in "${server_nodes[@]}"; do
        oarsh "$server_node" "pkill java" &
      done
      for pid in "${server_p_ids[@]}"; do
        wait "$pid"
        echo -n "${pid} "
      done
      echo "Servers Killed"

      echo -e "$BLUE Backing up zk data $NC"
      unset backup_pids
      backup_pids=()
      for server_node in "${server_nodes[@]}"; do
        oarsh "$server_node" "mkdir /tmp/zookeeper_${OAR_JOB_ID}; rm -r /tmp/zookeeper_${OAR_JOB_ID}/*; cp -r /tmp/zookeeper/* /tmp/zookeeper_${OAR_JOB_ID}/" &
        backup_pids+=($!)
      done
      for pid in "${backup_pids[@]}"; do
        wait "$pid"
      done

      for reads_per in "${reads_list[@]}"; do # ---------------------------  READS_PER
        echo -e "$GREEN -- -- -- STARTING READS PERCENTAGE  $NC$reads_per"

        writes_per="$((100 - reads_per))"
        echo -e "$GREEN -- -- -- - ${NC}r:${reads_per} w:${writes_per}"

        exp_path_client="../logs/zk_strong/${exp_name}/client/${n_servers}/${reads_per}/${payload}/original/${run}"
        exp_path_server="../logs/zk_strong/${exp_name}/server/${n_servers}/${reads_per}/${payload}/original/${run}"

        mkdir -p "${exp_path_client}"
        mkdir -p "${exp_path_server}"

        for n_threads in "${threads_list[@]}"; do # -------------------- N_THREADS
          echo -e "$GREEN -- -- -- -- -- -- -- -- STARTING THREADS $NC$n_threads"
          echo -e "$GREEN -- -- -- -- -- -- -- -- - $NC$exp_path_client/$n_threads"

          rm -r "${exp_path_client}"/"${n_threads}"_*
          rm -r "${exp_path_server}"/"${n_threads}"_*

          ((current_run = current_run + 1))
          echo -e "$GREEN RUN ${current_run}/${total_runs} - ($(((current_run - 1) * 100 / total_runs))%) ($start_date) $NC"
          sleep 6

          unset backup_pids
          backup_pids=()
          echo -e "$BLUE Restoring backup data $NC"
          for server_node in "${server_nodes[@]}"; do
            oarsh "$server_node" "rm -r /tmp/zookeeper/* ; cp -r /tmp/zookeeper_${OAR_JOB_ID}/* /tmp/zookeeper/" &
            backup_pids+=($!)
          done
          for pid in "${backup_pids[@]}"; do
            wait "$pid"
          done

          echo -e "$BLUE Starting servers and sleeping 8 $NC"
          #echo "USING ASSERTIONS!!!!!!!!!"
          unset server_p_ids
          server_p_ids=()
          for server_node in "${server_nodes[@]}"; do
            oarsh "$server_node" "cd chainpaxos/apache-zookeeper-3.7.0-bin && \
            bin/zkServer.sh start-foreground ${OAR_JOB_ID}.cfg" 2>&1 | sed "s/^/[s-$server_node] /" &
            server_p_ids+=($!)
          done

          sleep 8
          echo "Starting clients and waiting for them to finish"
          unset client_p_ids
          client_p_ids=()
          i=0
          for node in "${client_nodes[@]}"; do
            oarsh "$node" "cd chainpaxos/client && java -cp chain-client.jar:. \
                      site.ycsb.Client -t -s -P config.properties \
                      -p db=ZKClient -p hosts=$servers_without_port \
                      -p zookeeper.syncRead=true \
											-threads $n_threads -p fieldlength=$payload \
											-p readproportion=${reads_per} -p insertproportion=0 \
											-p updateproportion=${writes_per} \
											| tee ${exp_path_client}/${n_threads}_${node}.log" |& sed "s/^/[c-$node] /" &
            #> ${exp_path_client}/${n_threads}_${node}.log" 2>&1 | sed "s/^/[c-$node] /" &
            client_p_ids+=($!)
            i=$((i + 1))
          done

          for pid in "${client_p_ids[@]}"; do
            wait "$pid"
            echo -n "${pid} "
          done
          echo "Clients done"
          sleep 1
          echo "Killing servers"
          for server_node in "${server_nodes[@]}"; do
            oarsh "$server_node" "pkill java" &
          done
          for pid in "${server_p_ids[@]}"; do
            wait "$pid"
            echo -n "${pid} "
          done
          echo "Servers Killed"
          sleep 1
        done #n_threads
      done   #reads_per
    done     #n_server
  done       #payload
done         #run
echo -e "$BLUE -- -- -- -- -- -- -- -- All tests completed $NC"
exit
