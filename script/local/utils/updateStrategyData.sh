#!/bin/bash
if [ $# -ne 2 ]; then
    echo "Usage: ./updateStrategyData.sh <strategy_address> <allocation>"
    exit 1
fi

source .env
strategy_address=$1
allocation=$2
maxUint=115792089237316195423570985008687907853269984665640564039457584007913129639935

cast send $VAULT --private-key $VAULT_ADMIN_PRIVATE_KEY "updateStrategyData(address,uint256,uint256,uint256,uint256)" $strategy_address $allocation $maxUint 0 0
