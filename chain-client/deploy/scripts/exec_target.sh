#!/usr/bin/env bash

# ----------------------------------- CONSTANTS -------------------------------
xmx="85G"
xms="85G"

RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ----------------------------------- PARSE PARAMS ----------------------------

zoourl="localhost"
weights=""
startrun=1

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --expname)
    expname="$2"
    shift # past argument
    shift # past value
    ;;
		--nclients)
    nclients="$2"
    shift # past argument
    shift # past value
    ;;
    --nruns)
    nruns="$2"
    shift # past argument
    shift # past value
    ;;
    --startrun)
    startrun="$2"
    shift # past argument
    shift # past value
    ;;
    --payloads)
    payloadsarg="$2"
    shift # past argument
    shift # past value
    ;;
    --batchsizes)
    batchsizearg="$2"
		shift # past argument
    shift # past value
    ;;
		--nservers)
    nserversarg="$2"
		shift # past argument
    shift # past value
    ;;
		--algs)
    algsarg="$2"
		shift # past argument
    shift # past value
    ;;
    		--readsper)
		readsarg="$2"
		shift # past argument
		shift # past value
		;;
		--frontends)
		frontendsarg="$2"
		shift # past argument
		shift # past value
		;;
		--threads)
    threadsarg="$2"
		shift # past argument
    shift # past value
    ;;
		--zoourl)
    zoourl="$2"
		shift # past argument
    shift # past value
    ;;
	--weights)
    weights="$2"
    shift
    shift
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -z "${expname}" ]]; then
  echo "expname not set"; exit
fi
if [[ -z "${nclients}" ]]; then
  echo "nclients not set"
	exit
fi
if [[ -z "${nruns}" ]]; then
  echo "nruns not set"
	exit
fi
if [[ -z "${payloadsarg}" ]]; then
  echo "payloads not set"
	exit
fi
if [[ -z "${batchsizearg}" ]]; then
  echo "batchsizes not set"
	exit
fi
if [[ -z "${nserversarg}" ]]; then
  echo "nservers not set"
	exit
fi
if [[ -z "${algsarg}" ]]; then
  echo "algs not set"
	exit
fi
if [[ -z "${readsarg}" ]]; then
  echo "readsper not set"
	exit
fi
if [[ -z "${frontendsarg}" ]]; then
  echo "frontends not set"
	exit
fi
if [[ -z "${threadsarg}" ]]; then
  echo "threads not set"
	exit
fi

allnodes=`./nodes.sh`
startdate=`date +"%H:%M:%S"`
nnodes=`wc -l <<< $allnodes`
clientnodes=`tail -n $nclients <<< $allnodes`
IFS=', ' read -r -a payloadslist <<< "$payloadsarg"
IFS=', ' read -r -a batchsizelist <<< "$batchsizearg"
IFS=', ' read -r -a nserverslist <<< "$nserversarg"
IFS=', ' read -r -a algslist <<< "$algsarg"
IFS=', ' read -r -a readslist <<< "$readsarg"
IFS=', ' read -r -a frontendslist <<< "$frontendsarg"
IFS=', ' read -r -a threadslist <<< "$threadsarg"

totalruns=$((${nruns}*${#payloadslist[@]}*${#batchsizelist[@]}*${#nserverslist[@]}*${#algslist[@]}*${#readslist[@]}*${#frontendslist[@]}*${#threadslist[@]}))

# ----------------------------------- LOG PARAMS ------------------------------
echo -e $BLUE"\n ---- CONFIG ---- " $NC
echo -e $GREEN" expname: " $NC								${expname}
echo -e $GREEN" clients (${nclients}): " $NC	$clientnodes
echo -e $GREEN" nruns: " $NC										${nruns}
echo -e $GREEN" startrun: " $NC										${startrun}
echo -e $GREEN" n servers: " $NC							${nserverslist[@]}
echo -e $GREEN" readspercent: " $NC						${readslist[@]}
echo -e $GREEN" payloads: " $NC								${payloadslist[@]}
echo -e $GREEN" batches: " $NC								${batchsizelist[@]}
echo -e $GREEN" algs: " $NC										${algslist[@]}
echo -e $GREEN" frontends: " $NC							${frontendslist[@]}
echo -e $GREEN" n threads: " $NC							${threadslist[@]}
echo -e $GREEN" ---------- " $NC
echo -e $GREEN" number of runs:  " $NC${totalruns}
echo -e $BLUE" ---- END CONFIG ---- \n" $NC

currentrun=0
sleep 5

# ----------------------------------- START EXP -------------------------------

for run in $(seq $startrun $(($nruns+$startrun-1))) # ------------------------------------------- RUN
do
	echo -e $GREEN" -- STARTING RUN " $NC$run

	for nservers in "${nserverslist[@]}" # --------------------------- N_SERVERS
	do
		echo -e $GREEN" -- -- STARTING NSERVERS " $NC$nservers
		maxconcurrentfails=$(( $nservers / 2 ))
		quorumsize=$(( $nservers / 2 + 1 ))
		echo -e $GREEN" -- -- - Quorumsize: " $NC$quorumsize
		echo -e $GREEN" -- -- - Maxconcurrentfails: " $NC$maxconcurrentfails
		if (( $nclients + $nservers > $nnodes )); then
			echo -e $RED"Not enough nodes!"$NC
			exit
		fi
		servernodes=`head -n $nservers <<< $allnodes`
		echo -e $GREEN" -- -- - Servers: " $NC$servernodes
		serverswithoutport=""
		for snode in $servernodes; do
			serverswithoutport=${serverswithoutport}${snode}","
		done
		serverswithoutport=${serverswithoutport::-1}

		for readsper in "${readslist[@]}" # ---------------------------  READS_PER
		do
			echo -e $GREEN" -- -- -- STARTING READS PERCENTAGE " $NC$readsper

			writesper="$((100-$readsper))"
			echo -e $GREEN" -- -- -- - " ${NC}r:${readsper} w:${writesper}

			for payload in "${payloadslist[@]}" # ------------------------- PAYLOADS
			do
				echo -e $GREEN" -- -- -- -- STARTING PAYLOAD " $NC$payload

				for batchsize in "${batchsizelist[@]}" # ------------------- BATCH_SIZE
				do
					echo -e $GREEN" -- -- -- -- -- STARTING BATCHSIZE " $NC$batchsize

					for alg in "${algslist[@]}" # ----------------------------------- ALG
					do
						echo -e $GREEN" -- -- -- -- -- -- STARTING ALG " $NC$alg

						for frontends in "${frontendslist[@]}" # ---------------- FRONTENDS
						do
							echo -e $GREEN" -- -- -- -- -- -- -- STARTING FRONTENDS " $NC$frontends

							exppath="${expname}/${nservers}/${readsper}/${payload}/${batchsize}/${alg}/${frontends}/${run}"

							mkdir -p ~/client/results/${exppath}
							mkdir -p ~/server/logs/${exppath}

							for nthreads in "${threadslist[@]}" # -------------------- NTHREADS
							do
								echo -e $GREEN" -- -- -- -- -- -- -- -- STARTING THREADS " $NC$nthreads
								echo -e $GREEN" -- -- -- -- -- -- -- -- - " $NC$exppath/$nthreads

								rm -r ~/client/results/${exppath}/${nthreads}_*
								rm -r ~/server/logs/${exppath}/${nthreads}_*

								((currentrun=currentrun+1))
								echo -e $GREEN" RUN ${currentrun}/${totalruns} - ($(( (currentrun-1)*100/totalruns ))%) ($startdate)" $NC
								sleep 6

								echo -e $BLUE "Starting servers and sleeping 8" $NC
								#echo "USING ASSERTIONS!!!!!!!!!"
								unset serverpids
								serverpids=()
								leadertimeout=7000
								for servernode in $servernodes
								do
									oarsh $servernode "cd server && java -Xmx${xmx} -Xms${xms} \
											-Dlog4j.configurationFile=config/log4j2.xml \
											-DlogFilename=${exppath}/${nthreads}_${servernode} \
											-cp consensus.jar main.Main config/config.properties $alg \
											initial_membership=$serverswithoutport quorum_size=$quorumsize \
											read_response_bytes=$payload zookeeper_url=$zoourl \
											batch_size=$batchsize local_batch_size=$batchsize \
											n_frontends=$frontends leader_timeout=$leadertimeout \
											max_concurrent_fails=$maxconcurrentfails" 2>&1 | sed "s/^/[s-$servernode] /" &
									sleep 1
									serverpids+=($!)
									leadertimeout=$((leadertimeout+3000))
								done
								sleep 15
								echo "Starting clients and sleeping 70"
								unset pids
								pids=()
								idx=-1
								for node in $clientnodes
								do
									idx=$((idx+1))
									oarsh $node "cd client && java -Dlog4j.configurationFile=log4j2.xml \
											-DlogFilename=${exppath}/${nthreads}_${node} \
											-cp chain-client.jar site.ycsb.Client -t -s -P config.properties \
											-threads $nthreads -p node_number=$((idx+1)) -p fieldlength=$payload \
											-p hosts=$serverswithoutport -p readproportion=${readsper} -p insertproportion=${writesper} \
											-p n_frontends=$frontends -p weights=$weights \
											-target 5000 \
											> results/${exppath}/${nthreads}_${node}.log" 2>&1 | sed "s/^/[c-$node] /" &
									pids+=($!)
								done
								sleep 65
								echo "Killing clients"
								for node in $clientnodes
								do
									oarsh $node "pkill java" &
								done
								for pid in ${pids[@]}; do
									wait $pid
									echo -n "${pid} "
								done
								echo "Clients Killed"
								sleep 1
								echo "Killing servers"
								for servernode in $servernodes
								do
									oarsh $servernode "pkill java" &
								done
								for pid in ${serverpids[@]}; do
									wait $pid
									echo -n "${pid} "
								done
								echo "Servers Killed"
								sleep 1
							done #nthreads
						done #frontends
					done #alg
				done #batch_size
			done #payload
		done #readsper
	done #nserver
done #run
echo -e $BLUE" -- -- -- -- -- -- -- -- All tests completed"$NC
exit