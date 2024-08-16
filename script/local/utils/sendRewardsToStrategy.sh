#!/bin/bash
if [ $# -ne 2 ]; then
    echo "Usage: ./sendRewardsToStrategy.sh <strategy_address> <wei_amount>"
    exit 1
fi

source .env
weth=$(cast send $WETH --private-key $DEPLOYER_PRIVATE_KEY "transfer(address,uint256)" $1 $2)
echo "WETH Balance of Strategy:" $(cast call $WETH "balanceOf(address)(uint256)" $1)
