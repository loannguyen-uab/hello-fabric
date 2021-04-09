#!/bin/bash

#1. env setting
export PATH=${PWD}/bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export VERBOSE=true


# variants
IMAGETAG="latest"

# use this as the default docker-compose yaml definition
COMPOSE_FILE_BASE=docker/docker-compose-test-net.yaml
# docker-compose.yaml file if you are using couchdb
COMPOSE_FILE_COUCH=docker/docker-compose-couch.yaml
# certificate authorities compose file
COMPOSE_FILE_CA=docker/docker-compose-ca.yaml

#2. functions

# After we create the org crypto material and the system channel genesis block,
# we can now bring up the peers and orderering service. By default, the base
# file for creating the network is "docker-compose-test-net.yaml" in the ``docker``
# folder. This file defines the environment variables and file mounts that
# point the crypto material and genesis block that were created in earlier.

# Bring up the peer and orderer nodes using docker compose.
function networkUp() {

  #checkPrereqs
  # generate artifacts if they don't exist
  #if [ ! -d "organizations/peerOrganizations" ]; then
    createOrgs
    createConsortium
  #fi

  COMPOSE_FILES="-f ${COMPOSE_FILE_BASE}"

  if [ "${DATABASE}" == "couchdb" ]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
  fi

  IMAGE_TAG=$IMAGETAG docker-compose ${COMPOSE_FILES} up -d 2>&1

  docker ps -a
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network"
    exit 1
  fi
}


# Tear down running network
function networkDown() {
  # stop org3 containers also in addition to org1 and org2, in case we were running sample to add org3
  docker-compose -f $COMPOSE_FILE_BASE -f $COMPOSE_FILE_COUCH -f $COMPOSE_FILE_CA down --volumes --remove-orphans
  #docker-compose -f $COMPOSE_FILE_COUCH_ORG3 -f $COMPOSE_FILE_ORG3 down --volumes --remove-orphans
  # Don't remove the generated artifacts -- note, the ledgers are always removed
  
  if [ "$MODE" != "restart" ]; then
    # Bring down the network, deleting the volumes
    #Cleanup the chaincode containers
    clearContainers

    #Cleanup images
    removeUnwantedImages
    
    # remove orderer block and other channel configuration transactions and certs
    rm -rf outputs/system-genesis-block/*.block outputs/organizations/peerOrganizations outputs/organizations/ordererOrganizations
    
    ## remove fabric ca artifacts
    rm -rf outputs/organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db
    rm -rf outputs/organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db
    rm -rf outputs/organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db
    rm -rf outputs/addOrg3/fabric-ca/org3/msp addOrg3/fabric-ca/org3/tls-cert.pem addOrg3/fabric-ca/org3/ca-cert.pem addOrg3/fabric-ca/org3/IssuerPublicKey addOrg3/fabric-ca/org3/IssuerRevocationPublicKey addOrg3/fabric-ca/org3/fabric-ca-server.db


    # remove channel and script artifacts
    #rm -rf channel-artifacts log.txt fabcar.tar.gz fabcar

  fi
}

#create the organizations
function createOrgs() {
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi

  echo "Creating Org1 Identities"
  set -x
  cryptogen generate --config=./config/organizations/cryptogen/crypto-config-org1.yaml --output="outputs/organizations"
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate certificates..."
    exit 1
  fi

  echo "Creating Org2 Identities"
  set -x
  cryptogen generate --config=./config/organizations/cryptogen/crypto-config-org2.yaml --output="outputs/organizations"
  res=$?
  { set +x; } 2>/dev/null
  if [ $res -ne 0 ]; then
    fatalln "Failed to generate certificates..."
  fi

  echo "Creating Orderer Identities"
  set -x
  cryptogen generate --config=./config/organizations/cryptogen/crypto-config-orderer.yaml --output="outputs/organizations"
  res=$?
  { set +x; } 2>/dev/null
  if [ $res -ne 0 ]; then
    fatalln "Failed to generate certificates..."
  fi
}

# Generate orderer system channel genesis block.
function createConsortium() {
  
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi
	
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  set -x
  configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock ./outputs/system-genesis-block/genesis.block
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate orderer genesis block..."
    exit 1
  fi
}

# Obtain CONTAINER_IDS and remove them
# TODO Might want to make this optional - could clear other containers
# This function is called when you bring a network down
function clearContainers() {
  CONTAINER_IDS=$(docker ps -a | awk '{print $1}')
  #CONTAINER_IDS=$(docker ps -a)
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}


#3. main
if [[ $# -lt 1 ]] ; then
  #printHelp
  exit 0
else
  MODE=$1
  shift
fi

if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "createChannel" ]; then
  createChannel
elif [ "${MODE}" == "deployCC" ]; then
  deployCC
elif [ "${MODE}" == "down" ]; then
  networkDown
elif [ "${MODE}" == "restart" ]; then
  networkDown
  networkUp
else
  #printHelp
  exit 1
fi



