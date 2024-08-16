#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage: ./removeStrategy.sh <strategy>"
	exit 1
fi

source .env

# Remove strategy
remove=$(cast send $VAULT --private-key $VAULT_ADMIN_PRIVATE_KEY "exitStrategy(address)()" $1)
echo "Removed strategy $1..."

echo "----------------------------------------------------------------------------------------"
echo "[WARNING] - Remember to DEACTIVATE strategy $1 from DB"
echo "----------------------------------------------------------------------------------------"

exit 0
