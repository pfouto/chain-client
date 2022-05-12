#!/usr/bin/env bash

# ----------------------------------- CONSTANTS -------------------------------
xmx=$(cat xmx)
xms=$(cat xmx)

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
  --algs)
    algs_arg="$2"
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
if [[ -z "${algs_arg}" ]]; then
  echo "algs not set"
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
IFS=', ' read -r -a algs_list <<<"$algs_arg"
IFS=', ' read -r -a reads_list <<<"$reads_arg"
IFS=', ' read -r -a threads_list <<<"$n_threads_arg"

total_runs=$((n_runs * ${#payloads_list[@]} * ${#n_servers_list[@]} * ${#algs_list[@]} * ${#reads_list[@]} * ${#threads_list[@]}))

# ----------------------------------- LOG PARAMS ------------------------------
echo -e "$BLUE\n ---- CONFIG ----  $NC"
echo -e "$GREEN exp_name: $NC \t\t\t${exp_name}"
echo -e "$GREEN clients (${n_clients}): $NC \t\t\t${client_nodes[*]}"
echo -e "$GREEN n_runs: $NC	\t\t${n_runs}"
echo -e "$GREEN start_run: $NC \t\t\t${start_run}"
echo -e "$GREEN n_servers: $NC \t\t\t${n_servers_list[*]}"
echo -e "$GREEN reads_percent: $NC \t\t${reads_list[*]}"
echo -e "$GREEN payloads: $NC \t\t\t${payloads_list[*]}"
echo -e "$GREEN algorithms:  $NC \t\t\t${algs_list[*]}"
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

  for n_servers in "${n_servers_list[@]}"; do # --------------------------- N_SERVERS
    echo -e "$GREEN -- -- STARTING N_SERVERS $NC$n_servers"
    max_concurrent_fails=$((n_servers / 2))
    quorum_size=$((n_servers / 2 + 1))
    echo -e "$GREEN -- -- - Quorum size: $NC$quorum_size"
    echo -e "$GREEN -- -- - Max concurrent fails: $NC$max_concurrent_fails"
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

    for reads_per in "${reads_list[@]}"; do # ---------------------------  READS_PER
      echo -e "$GREEN -- -- -- STARTING READS PERCENTAGE  $NC$reads_per"

      writes_per="$((100 - reads_per))"
      echo -e "$GREEN -- -- -- - ${NC}r:${reads_per} w:${writes_per}"

      for payload in "${payloads_list[@]}"; do # ------------------------- PAYLOADS
        echo -e "$GREEN -- -- -- -- STARTING PAYLOAD $NC$payload"

        for alg in "${algs_list[@]}"; do # ----------------------------------- ALG
          echo -e "$GREEN -- -- -- -- -- -- STARTING ALG $NC$alg"

          exp_path_client="$HOME/chainpaxos/logs/geo/${exp_name}/client/${n_servers}/${reads_per}/${payload}/${alg}/${run}"
          exp_path_server="$HOME/chainpaxos/logs/geo/${exp_name}/server/${n_servers}/${reads_per}/${payload}/${alg}/${run}"

          for server_node in "${server_nodes[@]}"; do
              ssh "$server_node" "mkdir -p ${exp_path_server}"
          done

          for node in "${client_nodes[@]}"; do
              ssh "$node" "mkdir -p ${exp_path_client}"
          done

          for n_threads in "${threads_list[@]}"; do # -------------------- N_THREADS
            echo -e "$GREEN -- -- -- -- -- -- -- -- STARTING THREADS $NC$n_threads"
            echo -e "$GREEN -- -- -- -- -- -- -- -- - $NC$exp_path_client/$n_threads"

            for server_node in "${server_nodes[@]}"; do
                ssh "$server_node" "rm -r ${exp_path_server}/${n_threads}_*"
            done

            for node in "${client_nodes[@]}"; do
                ssh "$node" "rm -r ${exp_path_client}/${n_threads}_*"
            done

            ((current_run = current_run + 1))
            echo -e "$GREEN RUN ${current_run}/${total_runs} - ($(((current_run - 1) * 100 / total_runs))%) ($start_date) $NC"
            sleep 2

            echo -e "$BLUE Starting servers and sleeping 8 $NC"
            #echo "USING ASSERTIONS!!!!!!!!!"
            unset server_p_ids
            server_p_ids=()
            for server_node in "${server_nodes[@]}"; do
              ssh "$server_node" "cd chainpaxos/server && java -Xmx${xmx} -Xms${xms} \
											-Dlog4j.configurationFile=log4j2.xml \
											-Djava.net.preferIPv4Stack=true \
											-DlogFilename=${exp_path_server}/${n_threads}_${server_node} \
											-cp chain.jar:. app.HashMapApp algorithm=$alg initial_membership=$servers_without_port \
											initial_state=ACTIVE batch_interval=100 local_batch_interval=100 \
											quorum_size=$quorum_size read_response_bytes=$payload zookeeper_url=$zoo_url \
											batch_size=10 local_batch_size=10 n_frontends=1 \
											max_concurrent_fails=$max_concurrent_fails" 2>&1 | sed "s/^/[s-$server_node] /" &
              sleep 0.5
              server_p_ids+=($!)
            done
            sleep 8
            echo "Starting clients and waiting for them to finish"
            unset client_p_ids
            client_p_ids=()
            for node in "${client_nodes[@]}"; do
              ssh "$node" "cd chainpaxos/client && java -cp chain-client.jar \
                      site.ycsb.Client -t -s -P config.properties \
											-threads $n_threads -p fieldlength=$payload \
											-p maxexecutiontime=125 \
											-p hosts=${server_nodes[0]} -p n_frontends=1 \
											-p readproportion=${reads_per} -p insertproportion=${writes_per} \
											| tee ${exp_path_client}/${n_threads}_${node}.log" |& sed "s/^/[c-$node] /" &
              #> ${exp_path_client}/${n_threads}_${node}.log" 2>&1 | sed "s/^/[c-$node] /" &
              client_p_ids+=($!)
            done

            for pid in "${client_p_ids[@]}"; do
              wait "$pid"
              echo -n "${pid} "
            done
            echo "Clients done"
            sleep 1
            echo "Killing servers"
            for server_node in "${server_nodes[@]}"; do
              ssh "$server_node" "pkill java" &
            done
            for pid in "${server_p_ids[@]}"; do
              wait "$pid"
              echo -n "${pid} "
            done
            echo "Servers Killed"
            sleep 1
          done #n_threads
        done   #alg
      done     #payload
    done       #reads_per
  done         #nserver
done           #run
echo -e "$BLUE -- -- -- -- -- -- -- -- All tests completed $NC"
exit
