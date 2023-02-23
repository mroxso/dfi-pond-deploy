#!/bin/bash

set -eu


usage() {
  echo 'Usage: . ./setup.sh <EMAIL> <DOMAIN> <RPC_USER> <RPC_PASSWORD>'
  exit
}


if [ "$#" -lt 2 ]
then
  usage
fi

LOC=$PWD
DATA_LOC=$LOC/data
LEVELDB_LOC=$LOC/leveldb
INDEX="https://snapshots-eu.sanc.ch"
SNAPSHOT_VERSION="latest"
POND_NODE="pond-node-$SNAPSHOT_VERSION.tar.gz"
POND_WHALE="pond-whale-$SNAPSHOT_VERSION.tar.gz"
NETWORK="ocean"
EMAIL=$1
DOMAIN=$2
RPC_USER=$(openssl rand -hex 48 | cut -c1-12)
RPC_PASSWORD=$(openssl rand -hex 48 | cut -c1-12)

# Injecting rpc username and password if supplied by user
sed -i -e "s/whale-rpcuser/$RPC_USER/g" $LOC/docker-compose.yml
sed -i -e "s/whale-rpcpassword/$RPC_PASSWORD/g" $LOC/docker-compose.yml

# Check if Disk space is sufficient for downloading and unpacking snapshots
df  .| grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $4 " " $1 }' | while read output;
do
  usep=$(echo $output | awk '{ print $1}' | cut -d'%' -f1  )
  partition=$(echo $output | awk '{ print $2 }' )
  if [ $usep -lt 199229440 ]; then
    echo "Fail: Partition \"$partition\" is less than 190Gb needed for Pond snapshot downloads."
    exit 1
  fi
done

mkdir $DATA_LOC $LEVELDB_LOC

# Download defichain & leveldb snapshots
echo "Downloading Pond Whale snapshot"
wget $INDEX/$POND_WHALE
if [ ! -f "${POND_WHALE}" ]; then
  echo "${POND_WHALE}: File not found or is empty"
  exit 1
fi
echo "Unpacking Pond Whale snapshot"
tar -xzvf $POND_WHALE -C $LEVELDB_LOC
rm -rf $POND_WHALE

echo "Downloading Pond Node snapshot"
wget $INDEX/$POND_NODE
if [ ! -f "${POND_NODE}" ]; then
  echo "${POND_NODE}: File not found or is empty"
  exit 1
fi
echo "Unpacking Pond Node snapshot"
tar -xzvf $POND_NODE -C $DATA_LOC
rm -rf $POND_NODE

sudo chown -R ${UID}:${UID} $LEVELDB_LOC
sudo chown -R ${UID}:${UID} $DATA_LOC


# Inject user parameters into traefik config
echo "Adding Pond overlay network"

sed -i -e "s/POND_EMAIL/$EMAIL/g" $LOC/traefik.toml
sed -i -e "s/POND_DOMAIN/$DOMAIN/g" $LOC/dynamic_conf.yml

# Create docker network
echo "Creating Pond local Network"
if [ -z $(docker network ls --filter name=^${NETWORK}$ --format="{{ .Name }}") ] ; then
     docker network create ${NETWORK} ;
fi

# Start Pond
echo "Pond starting.."

if ! docker-compose up -d &> /dev/null
then
    docker compose up -d &> /dev/null
    if [ $? -ne 0 ]
    then
      echo "\"docker compose \" could not be found"
      exit 1
    fi
fi
