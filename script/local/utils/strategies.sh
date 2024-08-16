#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: ./strategies <strategy>"
	exit 1
fi

source .env
resp=$(cast call $VAULT "strategies(address)((uint16,uint16,uint48,uint48,uint128,uint128,uint128,uint128,uint128,bool))" $1)
echo $resp
exit 0
