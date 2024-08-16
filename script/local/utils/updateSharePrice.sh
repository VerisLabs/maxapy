#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: ./updateSharePrice.sh <strategy_address>"
	exit 1
fi

source .env
echo "Previous SP:" $(cast call $VAULT "sharePrice()(uint256)")
harvest=$(cast send $1 --private-key $KEEPER1_PRIVATE_KEY "harvest(uint256,uint256,uint256,address)" 0 0 0 $VAULT)
echo "Final SP:" $(cast call $VAULT "sharePrice()(uint256)")
exit 0
