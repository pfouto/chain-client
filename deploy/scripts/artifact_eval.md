## Reproducing experiments

This document describes how to reproduce the experiments on the article.
If the evaluator wishes to perform a simpler initial test, the README in the main repository (https://github.com/pfouto/chain) 
has instructions on how to run our artifact in a very simple setting (either in a single machine with docker, or 3 different machines).


### Paper setup

The experiments in the paper were conducted in the [Grid5000 testbed](https://www.grid5000.fr/w/Grid5000:Home), using
the [gros](https://www.grid5000.fr/w/Nancy:Hardware#gros) cluster which includes machines with the following configuration:

+ **CPU**: Intel Xeon Gold 5220 (Cascade Lake-SP, 2.20GHz, 1 CPU/node, 18 cores/CPU)
+ **Memory**:  96 GiB
+ **Network**: 25 Gbps (SR‑IOV)

Experiments were done using up to 11 physical machines of this cluster (1 coordinator + 3 clients + 3/5/7 servers).

Experiments involving geo-replication were done using up to 16 physical machines (1 coordinator + 10 clients + 3/5 servers)

The folder `deploy/scripts/g5k` includes all the scripts used to execute the experiments, with the file `deploy/scripts/g5k/exps` detailing the exact commands
that were run for each set of figures. However, since we assume that the reviewer does not have access to Grid5000, we will provide
instruction and scripts on how to run the experiments in a generic cluster.

---

**Note**: We assume that the evaluator does not have access to the Grid5000 testbed. If he does, then please contact us, and we will
provide instructions on how to reproduce our results there (which is easier than the instructions that follow).

---

### Requirements for reproducing results

To reproduce our experiments, the evaluator requires a cluster of machines, either physical or virtual (Azure, AWS, etc).
The requirements for those machines are as follows:

* They should be accessible via SSH with public key authentication, since the scripts to run the experiments will automatically deploy and terminate replicas and clients via SSH.
* They need to be able to communicate with each other (i.e., no firewall between them)
* They should be running linux (ideally Debian, as that is what we used, but any distribution should work)
* The only software dependency is Java (ideally openjdk 17)
* For the geo-replication experiments, root permissions are required in order to setup TC rules to emulate latency and bandwidth.

### Setup for reproducing results

#### Worker machines

First we need to move all the artifacts to the machines that will run the experiments.
There are 4 artifacts to setup: 

- the ChainPaxos implementation (which includes other consensus protocols);
- the ZooKeeper implementation that uses ChainPaxos instead of Zab;
- the original 3.7.0 ZooKeeper release;
- the YCSB client code;

The result of this step should be having a folder named `chainpaxos` in the user's home folder in each machine, with the following contents:

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

The steps to setup this file structure are as follows:

* Clone the repository https://github.com/pfouto/chain and then copy the folder deploy/server to the folder `/home/<your user>/chainpaxos/server` in each machine.
* Clone the repository https://github.com/pfouto/chain-client and then copy the folder deploy/client to the folder `/home/<your user>/chainpaxos/client` in each machine.
* Download ZooKeeper 3.7.0 from https://www.apache.org/dyn/closer.lua/zookeeper/zookeeper-3.7.0/apache-zookeeper-3.7.0-bin.tar.gz and then extract the archive to the folder `/home/<your user>/chainpaxos/zkOriginal` in each machine.
* Download the already compiled ChainPaxos version of ZooKeeper from https://github.com/pfouto/chain-zoo/raw/master/zookeeper-assembly/target/apache-zookeeper-3.7.0-bin.tar.gz and then extract the archive to the folder `/home/<your user>/chainpaxos/apache-zookeeper-3.7.0-bin` in each machine.
* Create the folder `/home/<your user>/chainpaxos/logs` in each machine.

Finally, we disable C-States in each worker machine:

    sudo apt-get install linux-cpupower && sudo cpupower idle-set -d 3

This is required to have more precise results, mainly in the latency experiments with low load (such as the one in figure 7).

#### Coordinator machine

Copy the `deploy/scripts/manual` folder from the `chain-client` repository to the machine that will coordinate the experiments and gather the results.
This can be any machine (one of the cluster machines or your personal workstation), as long as it has ssh access to the cluster machines.

In this folder there will be a `hosts` file. Add each of the worker machines IP address (or names) to this file, with one entry per line. 
The file comes with an example configuration, delete it and add your own IPs.
Additionally, set the contents of the file `xmx` to be the memory available for the Java process. In our experiments we set this value
to around 80% of the total available memory of the machine.

### Running experiments

#### Relevant details

Before providing the instruction to replicate the experiments, there are some important aspects that should be clarified:

* **Client configuration**: The way we conducted the performance experiments consisted in increasing the number of client threads until the throughput of the evaluated system reached its maximum value.
This means that we have an initial trial-and-error phase to find the number of clients required to saturate each system in each experiment.
As such, to reproduce our experiments in different hardware, the number of clients will be different from the one used in the examples in the following section.
Additionally, the number of clients that a single physical machine can handle is limited. We found that distributing the clients across 3 machines was a good balance for our setup.
* **Ring Paxos maximum concurrent instances**: Since Ring Paxos uses IP-multicast, in order to avoid saturating the network, resulting in a high percentage of packets being dropped,
we had to limit the number of maximum concurrent consensus instances. Again, this number will depend on the machines being used and their network configuration. The values used in our commands are the ones that presented better results in our testbed.
* **Chain Replication membership**: Our implementation of Chain Replication uses ZooKeeper as its membership management "oracle".
As such, during experiments that include Chain Replication, we run a (non-replicated) instance of ZooKeeper in one of the nodes (in our experiments we ran it on the coordinator).
All other protocols were implemented with static memberships (except ChainPaxos, of course), and thus do not require ZooKeeper. 
Note that this usage of ZooKeeper is completely unrelated to the experiments done in the ZooKeeper case-study in section 5.4 (figure 8).
* **Machine selection**: All scripts attempt to execute the experiments launching the consensus replicas (servers) and clients in the machines
declared in the `hosts` file. Consensus replicas are picked from top to bottom while client files are picked from the bottom to the top.
For instance, if you have 10 machines in the file, and execute an experiment with 5 servers and 3 clients, the first 5 machines
in the file will be the servers, while the last 3 will be the clients, with the remaining 2 machines being unused.
* **Aborting experiments**: If during the execution of the experiments for some reason you need to cancel them (e.g., to restart with different parameters),
the scripts `killall.sh` will connect to each worker machine and kill all running Java processes.

#### CPU bottleneck (Fig. 4)

To reproduce the results in Figure 4, first we launch a Zookeeper instance, required for Chain Replication, from the `chainpaxos` folder:
    
    zkOriginal/bin/zkServer.sh start zoo_sample.cfg

This can be launched either on the coordinator, or any of the worker replicas (preferably on the ones that will run the clients)

Then we executed the following scripts (that we got from the `deploy/scripts/manual` folder), sequentially:

    ./exec_cpu_threads.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3,7 --reads_per 0 \
        --algs chainrep,chain_mixed,uring,distinguished_piggy,multi,epaxos,esolatedpaxos \
        --zoo_url <zoo_url> --n_threads 1,2,5,10,20,50,100,200,300,400,500
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

The script starts by outputting the received configuration:

        ---- CONFIG ----  
        exp_name:  			test
        clients (3):  		gros-85.nancy.grid5000.fr gros-77.nancy.grid5000.fr 
                                    gros-80.nancy.grid5000.fr
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

The evaluator will probably want to use a lower number of `n_runs`.

The experiment consists in:

* Launching <n_servers> replicas of the given protocol.
* Launching <n_client> clients with <n_threads> client threads each. Clients execute operations in closed loop for 85 seconds
* Waiting for the clients to terminate
* Terminate the replicas
* Repeat for the next combination of parameters

The machines to be used as replicas are picked starting from the first as defined in the `hosts` file, while the machines
for clients are picked starting from the bottom.

Results for each experiment are saved in the following folder:

`$HOME/chainpaxos/logs/cpu_threads/<exp_name>/<server/client>/<n_servers>/<reads_per>/<payload>/<alg>/<run>`


#### Read Operations (Fig. 6)

The steps to reproduce these experiments are similar to the CPU bottleneck experiments. Simply execute the following scripts:

    ./exec_reads_strong.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3,7 --reads_per 0,95 --algs chain_mixed \
		--n_threads 1,2,5,10,20,50,100,150,200,300,500
    ./exec_reads_strong.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3,7 --reads_per 50,95 --algs esolatedpaxos \
		--n_threads 1,2,5,10,20,50,100,150,200,300,500
    ./exec_reads_strong.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 3 --reads_per 0,100 --algs esolatedpaxos \
		--n_threads 1,2,5,10,20,50,100,150,200,300,500
    ./exec_reads_strong.sh  --exp_name test --n_clients 3 --n_runs 3 --payloads 128 \
		--n_servers 7 --reads_per 0,100 --algs esolatedpaxos \
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

For this experiment to have accurate results, it is important that C-States are disabled on the machines.
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
rules to limit the bandwidth available in each machine, which requires the user to have root access.
For Debian, this requires installing the package `iproute2`
 
    apt-get install iproute2

Run the following script:

    ./setuptc_local_1gb.sh 7

Which will connect to the first 7 machines in the `hosts` file (the ones that will serve as replicas in the following experiments)
and limit their bandwidth to 1gb. To avoid having to enter passwords manually, it is best if the worker machines are setup to
allow the user to execute sudo without password.

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

After running the experiments, every worker machine will have all logs in the folder `/home/<your user>/chainpaxos/logs`.
To gather them, simply copy that folder to a single machine (with rsync for instance) and all logs should merge without any conflicts.

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

If you wish to generate graphs for your results all you need to do is mimic the file structure in the results repository (i.e. having the python scripts and a folder `logs` with your results in the same folder)
and then execute the python scripts. They should find your results and parse them.

Each python script has, in the beginning, a number of parameters that you can alter to match your experiments, for instance:
    
    n_threads = [100, 200, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000]
    n_clients = 10
    payload = 2048
    reads = 0
    n_servers = [3, 5]
    n_runs = 3

If you only ran a single run of each experiment, change `n_runs` to 1. 
If you only ran a subset of the number of client threads, remove some entries from the `n_threads` list, etc.