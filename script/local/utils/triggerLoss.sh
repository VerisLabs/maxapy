#!/bin/bash

if [ $# -ne 2 ]; then
	echo "Usage: ./triggerLoss <strategy> <amount>"
	exit 1
fi

source .env
strategy=$1
amount=$2

liquidate=$(cast send --private-key $DEPLOYER_PRIVATE_KEY $strategy "liquidatePosition(uint256)()" $amount)
trigger=$(cast send --private-key $DEPLOYER_PRIVATE_KEY $strategy "triggerLoss(uint256)()" $amount)
echo "Triggered loss of $amount for strategy $strategy"
exit 1
