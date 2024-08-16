#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: ./getAllocation <strategy_address>"
	exit 1;
fi

source .env
output=$(cast call $VAULT "strategies(address)((uint16,uint16,uint48,uint48,uint128,uint128,uint128,uint128,uint128,bool))" $1)

first_param=$(echo $output | awk -F', ' '{print $1}' | tr -d '(')

echo $first_param
exit 0

