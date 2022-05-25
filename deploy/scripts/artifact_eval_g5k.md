## Reproducing experiments on Grid5000

This document describes how to reproduce the experiments on the article using the Grid5000 testbed

### Paper setup

The experiments in the paper were conducted in the [Grid5000 testbed](https://www.grid5000.fr/w/Grid5000:Home), using
the [gros](https://www.grid5000.fr/w/Nancy:Hardware#gros) cluster which includes machines with the following configuration:

+ **CPU**: Intel Xeon Gold 5220 (Cascade Lake-SP, 2.20GHz, 1 CPU/node, 18 cores/CPU)
+ **Memory**:  96 GiB
+ **Network**: 25 Gbps (SR‑IOV)

Experiments were done using up to 11 physical machines of this cluster (1 coordinator + 3 clients + 3/5/7 servers).

Experiments involving geo-replication were done using up to 16 physical machines (1 coordinator + 10 clients + 3/5 servers)

---

### Setup for reproducing results

These instructions assume some knowledge of the Grid5000 testbed. If the evaluator needs more detailed steps about using Grid, or the instructions
are not clear enough, feel free to ask us for clarifications.

Start by creating a job. In the `nancy` frontend, execute the following command to create a job with 16 machines in the `gros` cluster:
    
    oarsub -p "cluster='gros'" -l nodes=16,walltime=X "sleep 10d"

Once the job is ready (you can check its status with the command `oarstat -u`), connect to it by using:

    oarsub -C <job_id>

Which should connect you to one of the machines in the job. This machine will be called the `coordinator` from now on.


First we need to set up all the artifacts in the home folder in grid5k.
There are 4 artifacts to set up:

- the ChainPaxos implementation (which includes other consensus protocols);
- the ZooKeeper implementation that uses ChainPaxos instead of Zab;
- the original 3.7.0 ZooKeeper release;
- the YCSB client code;

A script is provided to set this up. To execute it, issue the following commands in any folder in the coordinator machine:

`wget https://raw.githubusercontent.com/pfouto/chain-client/master/deploy/scripts/g5k/setupg5k.sh`

`chmod +x setupg5k.sh`

`./setupg5k.sh`

The script will create a folder `chainpaxos` in your home folder, download all the artifacts and setup the file structure
required for the experiment scripts to work correctly.

After the script executes, you should have a folder named `chainpaxos` in your home folder, with the following contents:

      /home/<user>/chainpaxos/
      ├── apache-zookeeper-3.7.0-bin -> ZooKeeper with ChainPaxos 
      │   │                            (from https://github.com/pfouto/chain-zoo)
      │   ├── bin
      │   ├── conf
      │   ├── docs
      │   ├── lib
      │   ├── LICENSE.txt
      │   ├── logs
      │   ├── NOTICE.txt
      │   ├── README.md
      │   └── README_packaging.md
      ├── client -> Client code (from https://github.com/pfouto/chain-client)
      │   ├── chain-client.jar
      │   ├── config.properties
      │   └── log4j.properties
      ├── repos -> folder used to clone repositories (not needed for experiments)
      │   ├── apache-zookeeper-3.7.0-bin.tar.gz
      │   ├── chain
      │   ├── chain-client
      │   └── chain-zoo
      ├── scripts -> scripts that will execute the experiments
      │   ├── exec_cpu_threads.sh
      │   ├── exec_geo_last.sh
      │   └── ...      
      ├── logs -> Where the experiment logs will end up
      ├── server -> Server code for all consensus solutions 
      │   │         (from https://github.com/pfouto/chain)
      │   ├── chain.jar
      │   ├── config.properties
      │   ├── log4j2.xml
      │   └── log4j.properties
      └── zkOriginal -> Original ZooKeeper 3.7.0 release
          ├── bin
          ├── conf
          ├── docs
          ├── lib
          ├── LICENSE.txt
          ├── logs
          ├── NOTICE.txt
          ├── README.md
          └── README_packaging.md

You may delete the `setupg5k.sh` and the `/home/<user>/chainpaxos/repos` folder if you wish.


As our implementation of Chain Replication uses ZooKeeper as its membership management "oracle", we need to
run a (non-replicated) instance of ZooKeeper while executing experiments with Chain Replication. In our experiments, we ran this
instance on the coordinator. To run it, execute the following command in the `coordinator` node from the `/home/<user>/chainpaxos` folder:

        zkOriginal/bin/zkServer.sh start zoo_sample.cfg

Which will start a ZooKeeper instance in the background. You can simply leave it running during all experiments and forget about it.
Note that this usage of ZooKeeper is completely unrelated to the experiments done in the ZooKeeper case-study in section 5.4 (figure 8).

Finally, in order to have more precise results, mainly in the latency experiments with low load, we disable C-States in each worker machine.
From the `/home/<user>/chainpaxos/scripts` folder, execute the following script:

    ./disable_cstates.sh

Don't forget to disable C-States and launch ZooKeeper again if your job ends, and you need to create a new one.


### Running experiments

**Note**: If during the execution of the experiments for some reason you need to cancel them (e.g., to restart with different parameters),
the command `./runcmdsync.sh "killall java"` (executed from the `scripts` folder) will connect to each worker machine and kill all running Java processes.

All following commands are to be executed from the folder `/home/<user>/chainpaxos/scripts`

#### CPU bottleneck (Fig. 4)

To reproduce the results in Figure 4, make sure you have an instance of ZooKeeper running on the `coordinator`, then 
executed the following scripts (that we got from the `deploy/scripts/manual` folder), sequentially:

    ./exec_cpu_threads.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3,7 --reads_per 0 \
        --algs chainrep,chain_mixed,uring,distinguished_piggy,multi,epaxos,esolatedpaxos \
        --zoo_url gros-XX --n_threads 1,2,5,10,20,50,100,200,300,400,500
    ./exec_cpu_threads.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3 --reads_per 0 --algs ringpiggy  --ring_insts 120 \
        --n_threads 1,2,5,10,20,50,100,200,300,400
    ./exec_cpu_threads.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 7 --reads_per 0 --algs ringpiggy  --ring_insts 250 \
        --n_threads 1,2,5,10,20,50,100,200,300,400


The parameters passed to the script are as follows:

* **exp_name** the name of the experiments, which defines the folder to where logs will be saved.
* **n_clients** the number of client machines to be used
* **n_runs** the number of repetition for each experiment. We used 5 for our results, but 3 (or maybe even less) should provide similar results.
* **payloads** the size of the payload of operations 
* **n_servers** the number of replicas to run
* **read_per** percentage of read operations
* **algs** the protocols to evaluate
* **zoo_url** the IP address of the machine running ZooKeeper (required for Chain Replication)
* **ring_insts** the maximum number of concurrent consensus instances in Ring Paxos
* **n_threads** the number of client threads (i.e. the number of clients being emulated) in *each* client machine

The only thing that needs to be adapted in the commands is the `zoo_url` (and maybe the number of runs) which should be 
set to the name of the `coordinator` node, since this is where ZooKeeper is running. For instance `--zoo_url gros-30`.

The script starts by outputting the received configuration:

        ---- CONFIG ----  
        exp_name:  			test
        clients (3):  		gros-115 gros-116 gros-117
        n_runs: 			3
        start_run:  		1
        n_servers:  		3 7
        reads_percent:  	        0
        payloads:  			128
        algorithms:   		chainrep chain_mixed uring distinguished_piggy 
                                    multi epaxos esolatedpaxos
        n threads:  		1 2 5 10 20 50 100 200 300 400 500
         ---------- 
        number of runs:  	        462
        ---- END CONFIG ----


And then executes an experiment *for every combination of parameters*, in this case 462 experiments 

`(7 different algorithms * 2 numbers of servers * 11 numbers of threads * 3 runs = 462)`

The evaluator will probably want to use a lower number of `n_runs`. Even with a single run, the results should be pretty close
to the ones presented in the paper.

The experiment consists in:

* Launching <n_servers> replicas of the given protocol.
* Launching <n_client> clients with <n_threads> client threads each. Clients execute operations in closed loop for 85 seconds
* Waiting for the clients to terminate
* Terminate the replicas
* Repeat for the next combination of parameters

The script automatically detects the machines in your job, picking the ones to be used as replicas from the top of the list, while the machines
for clients are picked starting from the bottom.

Results for each experiment are saved in the following folder:

`$HOME/chainpaxos/logs/cpu_threads/<exp_name>/<server/client>/<n_servers>/<reads_per>/<payload>/<alg>/<run>`


#### Read Operations (Fig. 6)

The steps to reproduce these experiments are similar to the CPU bottleneck experiments. Simply execute the following scripts:

    ./exec_reads_strong.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3,7 --reads_per 0 --algs chain_mixed \
		--n_threads 1,2,5,10,20,50,100,150,200,300,500
    ./exec_reads_strong.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3,7 --reads_per 100 --algs esolatedpaxos \
		--n_threads 1,2,5,10,20,50,100,150,200,300,500
    ./exec_reads_strong_extra.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3 --reads_per 50,95 --algs chain_delayed \
		--n_threads 1,2,5,10,20,50,100,150,200,300,500,600,750,1000,1500,2000
    ./exec_reads_strong_extra.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
       --n_servers 7 --reads_per 50,95 --algs chain_delayed \
       --n_threads 1,2,5,10,20,50,100,150,200,300,500,600,750,1000,1500,2000,3000,4000,5000

The behaviour and parameters of these scripts is similar to the cpu benchmark, with results being saved to:

`$HOME/chainpaxos/logs/read_strong/<exp_name>/<server/client>/<n_servers>/<reads_per>/<payload>/<alg>/<run>`

All the following experiments save the results to a similar folder, only changing the type of the experiment (the `read_strong` part of this path).

The difference between the `exec_reads_strong` and `exec_reads_strong_extra` is that in the last script, extra clients execute operations in order
to decrease the latency of read operations under low load.

#### Latency under low load (Fig. 7)

For this experiment to have accurate results, make sure that you disabled C-States, as explained previously.
Again, just like the previous ones, run the following commands (making sure ZooKeeper is running for Chain Replication):

    ./exec_lat_split.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 3,5,7 --reads_per 0 \
		--algs epaxos,esolatedpaxos --n_threads 14
    ./exec_lat_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 3,5,7 --reads_per 0 \
		--algs distinguished,multi --n_threads 14
    ./exec_lat_tail.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 3,5,7 --reads_per 0 --zoo_url <zoo_url> \
		--algs uring,chainrep --n_threads 14
    ./exec_lat_middle.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 3,5,7 --reads_per 0 \
		--algs chain_mixed --n_threads 14
    ./exec_lat_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 3 --ring_insts 120 --reads_per 0 \
		--algs ring --n_threads 14
    ./exec_lat_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 5 --ring_insts 200 --reads_per 0 \
		--algs ring --n_threads 14
    ./exec_lat_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
		--payloads 128 --n_servers 7 --ring_insts 250 --reads_per 0 \
		--algs ring --n_threads 14

With results being saved to:

`$HOME/chainpaxos/logs/latency/<exp_name>/<server/client>/<n_servers>/<reads_per>/<payload>/<alg>/<run>`

The difference between these scripts is the replica to which clients connect to, which is always optimized to minimize latency.

#### ZooKeeper case-study (Figure 8)

While the experiments using ZooKeeper are considerably different (using ChainPaxos on ZooKeeper instead of the key-value store application), the scripts are still similar to the previous ones:

    #Strong reads
    ./exec_zk_orig_strong.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 128 --n_servers 3,5,7 --reads_per 50,95 \
        --n_threads 1,2,5,10,20,30,50,75,100,150,200,250,300,350
    ./exec_zk_chain_strong.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 128 --n_servers 3,5,7 --reads_per 50,95 \
        --n_threads 1,2,5,10,20,30,50,75,100,150,200,250,300,350
    #Weak reads
    ./exec_zk_chain.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 128 --n_servers 3,5,7 --reads_per 50,95 \
        --n_threads 1,2,5,10,20,30,50,75,100,150,200,250,300,350
    ./exec_zk_orig.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 128 --n_servers 3,5,7 --reads_per 50,95 \
        --n_threads 1,2,5,10,20,30,50,75,100,150,200,250,300,350
    #Writes
    ./exec_zk_chain.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 128 --n_servers 3,5,7 --reads_per 0 \
        --n_threads 1,2,5,10,20,30,50,75,100,150,200,250,300,350,500
    ./exec_zk_orig.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 128 --n_servers 3,5,7 --reads_per 0 \
        --n_threads 1,2,5,10,20,30,50,75,100,150,200,250,300,350,500

These scripts create ZooKeeper configuration files for the experiment, launch ZooKeeper replicas, load data into them, and then execute client operations just like in the previous ones (with the difference that operations are znode operations instead of key-value store operations).



#### Network bottleneck (Figure 5):

While the scripts to execute the experiments of Figure 5 are still similar to the previous ones, these experiments require previous setup of [Linux Traffic Control](https://man7.org/linux/man-pages/man8/tc.8.html) (tc)
rules to limit the bandwidth available in each machine.

A script is provided to set up TC rules, just execute:

    ./setuptc_local_1gb.sh 7

**NOTE** After executing the `setuptc_local_1gb.sh` script, do *not* re-run previous experiments, as the limitations in bandwidth
will affect their results. We did not prepare a script to clear TC rules, so we require deleting the job and creating a new one
to repeat previous experiments.

Which will connect to the first 7 machines in your job (the ones that will serve as replicas in the following experiments)
and limit their bandwidth to 1gb.

Finally, make sure ZooKeeper is running and execute the following scripts:

    ./exec_net_threads_split.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 2048 --n_servers 3,7 --reads_per 0 --algs epaxos,esolatedpaxos \
        --n_threads 1,2,5,10,20,30,50,75,100,200,300,400,500
    ./exec_net_threads_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 2048 --n_servers 3,7 --reads_per 0 --zoo_url <zoo_url> \
        --algs chain_mixed,uring,distinguished_piggy,multi,chainrep \
        --n_threads 1,2,5,10,20,30,50,75,100,200,300,400,500
    ./exec_net_threads_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 2048 --n_servers 3 --reads_per 0 --algs ringpiggy --ring_insts 15 \
        --n_threads 1,2,5,10,20,30,50,75,100,200
    ./exec_net_threads_leader.sh  --exp_name test --n_clients 3 --n_runs 3 \
        --payloads 2048 --n_servers 7 --reads_per 0 --algs ringpiggy --ring_insts 20 \
        --n_threads 1,2,5,10,20,30,50,75,100,200

#### Geo-replication experiments (Figure 9):

Finally, to reproduce the geo-replication experiments of Figure 9, the process is very similar.
First we execute the script that will setup the TC rules. 

    ./setuptc_remote_1gb.sh 5 tc_latencies

**NOTE** This script should override the rules of the previous one, so you can execute these experiments after executing the previous ones.
However, once again, do *not* re-run previous experiments, as you will get wrong results.

The difference between this script and the previous one is that it also sets latencies between the replicas.
These latencies are defined in the `tc_latencies` file, as a matrix.

Then we run the scripts that will execute the experiments. As the latency of operations will be higher, we require more clients to saturate the protocols,
so for this experiment we use 10 client machines:

    ./exec_geo_leader.sh  --exp_name test --n_clients 10 --n_runs 3 --payloads 2048 \
        --n_servers 3 --reads_per 0 --algs multi,distinguished_piggy \
        --n_threads 100,200,500,1000,1500,2000
    ./exec_geo_leader.sh  --exp_name test --n_clients 10 --n_runs 3 --payloads 2048 \
        --n_servers 5 --reads_per 0 --algs multi,distinguished_piggy \
        --n_threads 100,200,500,1000,1500,2000
    ./exec_geo_split.sh  --exp_name test --n_clients 10 --n_runs 3 --payloads 2048 \
        --n_servers 3 --reads_per 0 --algs epaxos,esolatedpaxos \
        --n_threads 100,200,500,1000,1500,2000,2500,3000
    ./exec_geo_split.sh  --exp_name test --n_clients 10 --n_runs 3 --payloads 2048 \
        --n_servers 5 --reads_per 0 --algs epaxos,esolatedpaxos \
        --n_threads 100,200,500,1000,1500,2000,2500,3000
    ./exec_geo_last.sh  --exp_name test --n_clients 10 --n_runs 3 --payloads 2048 \
        --n_servers 3 --reads_per 0 --zoo_url <zoo_url> --algs chainrep,chain_mixed,uring \
        --n_threads 100,200,500,1000,1500,2000,2500,3000,4000
    ./exec_geo_last.sh  --exp_name test --n_clients 10 --n_runs 3 --payloads 2048 \
        --n_servers 5 --reads_per 0 --zoo_url <zoo_url> --algs chainrep,chain_mixed,uring \
        --n_threads 100,200,500,1000,1500,2000,2500,3000,4000,5000

### Gathering results and understanding the logs

After running the experiments, all logs will be in the folder `/home/<your user>/chainpaxos/logs`.

The repository in `https://github.com/pfouto/chain-results/` contains the raw results used in the article, that can be used
to compare with the obtained results.
The repository also contains the scripts that parse them to generate graphs.

The structure of the results folder will be the following: 

`/logs/<exp_type>/<exp_name>/<server/client>/<n_servers>/<reads_per>/<payload>/<alg>/<run>/<n_threads>_<machine>.log`

Where each client log file contains, in intervals of 10 seconds, the number of operations executed, the current throughput,
and the latency of executed operations. 

To parse these results, for each point of each graph, the graph generation scripts do the following:

1. Average the latency and sum the throughput of all clients for each time interval for each run
2. Average the throughput and latency of all time intervals for each run
3. Average the throughput and latency of each run, resulting in the point to draw in the graph.

If you wish to generate plots for your results all you need to do is clone the repository, and replace the files in the `logs`
folder (which are the raw results of the experiments conducted for the paper) with the logs from your experiments.
Then, execute the python scripts, which will parse the logs and create plots in the `graphs` folder.

Each python script has, in the beginning, a number of parameters that you can alter to match your experiments, for instance:
    
    n_threads = [100, 200, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000]
    n_clients = 10
    payload = 2048
    reads = 0
    n_servers = [3, 5]
    n_runs = 3

If you only ran a single run of each experiment, change `n_runs` to 1. 
If you only ran a subset of the number of client threads, remove some entries from the `n_threads` list, etc.