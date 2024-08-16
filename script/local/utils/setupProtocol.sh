#!/bin/bash

if [ $# -ne 0 ]; then
	echo "Usage: ./setupProtocol"
	exit 1
fi

source .env
echo "Getting 100 WETH and depositing..."
./script/local/utils/getWethAndDeposit.sh 100000000000000000000  
./script/local/utils/harvestAll.sh
./script/local/utils/logStatus.sh
