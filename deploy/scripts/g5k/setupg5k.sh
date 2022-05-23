#!/usr/bin/env bash

set -e

echo "----- Creating directory ~/chainpaxos and sub-dirs"
mkdir ~/chainpaxos
mkdir ~/chainpaxos/repos
mkdir ~/chainpaxos/client
mkdir ~/chainpaxos/server
mkdir ~/chainpaxos/logs
mkdir ~/chainpaxos/scripts
mkdir ~/chainpaxos/apache-zookeeper-3.7.0-bin


echo "----- Cloning repositories to ~/chainpaxos/repos"
cd ~/chainpaxos/repos
git clone https://github.com/pfouto/chain
git clone https://github.com/pfouto/chain-client
git clone https://github.com/pfouto/chain-zoo

echo "----- Copying client files to ~/chainpaxos/client"
cp ~/chainpaxos/repos/chain-client/deploy/client/* ~/chainpaxos/client

echo "----- Copying server files to ~/chainpaxos/server"
cp ~/chainpaxos/repos/chain/deploy/server/* ~/chainpaxos/server

echo "----- Copying experiments scripts to ~/chainpaxos/scripts"
cp ~/chainpaxos/repos/chain-client/deploy/scripts/g5k/* ~/chainpaxos/scripts
chmod +x ~/chainpaxos/scripts/*.sh

echo "----- Downloading original zookeeper and extracting to ~/chainpaxos/zkOriginal"
cd ~/chainpaxos/repos
wget https://archive.apache.org/dist/zookeeper/zookeeper-3.7.0/apache-zookeeper-3.7.0-bin.tar.gz
tar -xf apache-zookeeper-3.7.0-bin.tar.gz -C ~/chainpaxos/
mv ~/chainpaxos/apache-zookeeper-3.7.0-bin ~/chainpaxos/zkOriginal
cd ~/chainpaxos/zkOriginal/conf
sed -i -e '/tickTime=/ s/=.*/=500/' zoo_sample.cfg

echo "------ Extracting Chain-ZooKeeper to ~/chainpaxos/apache-zookeeper-3.7.0-bin"
tar -xf ~/chainpaxos/repos/chain-zoo/zookeeper-assembly/target/apache-zookeeper-3.7.0-bin.tar.gz -C ~/chainpaxos/

