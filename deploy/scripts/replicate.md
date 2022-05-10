## Reproducing experiments

### Paper setup

The experiments in the paper were conducted in the [Grid5000 testbed](https://www.grid5000.fr/w/Grid5000:Home), using
the [gros](https://www.grid5000.fr/w/Nancy:Hardware#gros) cluster which includes machines with the following configuration:
* **CPU**: Intel Xeon Gold 5220 (Cascade Lake-SP, 2.20GHz, 1 CPU/node, 18 cores/CPU)
* **Memory**:  96 GiB
* **Network**: 25 Gbps (SR‑IOV)

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

First we need to move all the artifacts to the machines that will run the experiments.
There are 4 artifacts to setup: 
* the ChainPaxos implementation (which includes other consensus protocols);
* the ZooKeeper implementation that uses ChainPaxos instead of Zab;
* the original 3.7.0 ZooKeeper release;
* the YCSB client code;

The result of this step should be having a folder named `chainpaxos` in the user's home folder in each machine, with the following contents:

      /home/<user>/chainpaxos/
      ├── apache-zookeeper-3.7.0-bin -> ZooKeeper with ChainPaxos (from https://github.com/pfouto/chain-zoo)
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
      ├── server -> Server code for all consensus solutions (from https://github.com/pfouto/chain)
      │   ├── chain.jar
      │   ├── config.properties
      │   ├── log4j2.xml
      │   └── log4j.properties
      └── zkOriginal -> Original ZooKeeper 3.7.0 releas (from https://www.apache.org/dyn/closer.lua/zookeeper/zookeeper-3.7.0/apache-zookeeper-3.7.0-bin.tar.gz)
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

Finally, copy the `deploy/scripts/manual` folder from the `chain-client` repository to the machine that will coordinate the experiments and gather the results.
This can be any machine (one of the cluster machines or your personal workstation), as long as it has ssh access to the cluster machines.

TODO: Set hosts file with machine names

### Running experiments

