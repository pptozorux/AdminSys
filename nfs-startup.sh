#!/bin/bash

BLUE='\e[1;34m'
NC='\e[0m' # No Color

set -euo pipefail

RAM="1024"
VLAN=""
server_TAP=""
client_TAP=""
MASTER_IMG_NAME="debian-testing-amd64"
LAB_NAME="nfs_lab"
SECOND_DISK_SIZE="32G"

usage() {
>&2 cat << EOF
Usage: $0
   [ -v | --vlan <vlan id> ]
   [ -s | --server-port <server vm port number> ]
   [ -c | --client-port <client vm port number> ]
   [ -h | --help ]
EOF
exit 1
}

ARGS=$(getopt -a -o v:s:c:h --long vlan:,server-port:,client-port:,help -- "$@")

eval set -- "${ARGS}"
while :
do
    case $1 in
        -v | --vlan)
            VLAN=$2
            shift 2
            ;;
        -s | --server-port)
            server_TAP=$2
            shift 2
            ;;
        -c | --client-port)
            client_TAP=$2
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        # -- means the end of the arguments; drop this, and break out of the while loop
        --)
            shift
            break
            ;;
        *) >&2 echo Unsupported option: "$1"
           usage
           ;;
      esac
done

if [[ -z "$VLAN" ]] || [[ "$VLAN" =~ [^[:digit:]] ]]; then
    echo "VLAN identifier is required"
    usage
fi

if [[ -z "$server_TAP" ]] || [[ "$server_TAP" =~ [^[:digit:]] ]]; then
    echo "server tap port number is required"
    usage
fi

if [[ -z "$client_TAP" ]] || [[ "$client_TAP" =~ [^[:digit:]] ]]; then
    echo "client tap port number is required"
    usage
fi

echo -e "~> iSCSI lab VLAN identifier: ${BLUE}${VLAN}${NC}"
echo -e "~> server VM tap port number: ${BLUE}${server_TAP}${NC}"
echo -e "~> client VM tap port number: ${BLUE}${client_TAP}${NC}"
tput sgr0

# Switch ports configuration
for p in ${server_TAP} ${client_TAP}
do
    echo "Configuring tap${p} port..."
    sudo ovs-vsctl set port tap${p} tag=${VLAN} vlan_mode=access
done

# Copy iSCSI server and client VMs image files
mkdir -p $HOME/vm/${LAB_NAME}
cd $HOME/vm/${LAB_NAME}/

for f in server_img client_img
do
    if [[ ! -f ${f}.qcow2 ]]; then
        echo "Copying ${f}.qcow2 image file..."
        cp $HOME/masters/${MASTER_IMG_NAME}.qcow2 $HOME/vm/${LAB_NAME}/${f}.qcow2
        cp $HOME/masters/${MASTER_IMG_NAME}.qcow2_OVMF_VARS.fd $HOME/vm/${LAB_NAME}/${f}.qcow2_OVMF_VARS.fd
    fi
done


for vm in server client
do
    # Launch iSCSI server VM
    tap=${vm}_TAP
    $HOME/vm/scripts/ovs-startup.sh ${vm}_img.qcow2 ${RAM} ${!tap} 
done

exit 0