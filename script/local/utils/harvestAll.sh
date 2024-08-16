#!/bin/bash

if [ $# -ne 0 ]; then
	echo "Usage: ./updateSharePrice.sh"
fi

source .env

echo "Harvesting all strategies..."
echo "Previous SP:" $(cast call $VAULT "sharePrice()(uint256)")

harvestYearn=$(cast send $YEARN_STRATEGY --private-key $KEEPER1_PRIVATE_KEY "harvest(uint256,uint256,uint256,address)" 0 0 0 $VAULT)
harvestConvex=$(cast send $CONVEX_STRATEGY --private-key $KEEPER1_PRIVATE_KEY "harvest(uint256,uint256,uint256,address)" 0 0 0 $VAULT)
harvestSommelier1=$(cast send $SOMMELIER_ST_ETH_STRATEGY --private-key $KEEPER1_PRIVATE_KEY "harvest(uint256,uint256,uint256,address)" 0 0 0 $VAULT)
harvestSommelier2=$(cast send $SOMMELIER_ST_ETH_DEPOSIT_ST_ETH_STRATEGY --private-key $KEEPER1_PRIVATE_KEY "harvest(uint256,uint256,uint256,address)" 0 0 0 $VAULT)

echo "Final SP:" $(cast call $VAULT "sharePrice()(uint256)")