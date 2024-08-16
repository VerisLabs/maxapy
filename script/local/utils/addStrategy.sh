#!/bin/bash
if [ $# -ne 1 ]; then
	echo "Usage: ./addStrategy.sh <strategy>"
	exit 1
fi

source .env

MAX_UINT=115792089237316195423570985008687907853269984665640564039457584007913129639935
addStrategy=$(cast send $VAULT --private-key $VAULT_ADMIN_PRIVATE_KEY "addStrategy(address,uint256,uint256,uint256,uint256)" $1 1 $MAX_UINT 0 0)

echo "Added new strategy $1 to VAULT"

exit 0
