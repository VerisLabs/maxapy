#!/bin/bash
source .env

# 1.- Share price
sharePrice=$(cast call $VAULT "sharePrice()(uint256)")

# 2.- [4eStrategy] estimatedTotalAssets
estimatedTotalAssetsYearn=$(cast call $YEARN_STRATEGY "estimatedTotalAssets()(uint256)")
estimatedTotalAssetsConvex=$(cast call $CONVEX_STRATEGY "estimatedTotalAssets()(uint256)")
estimatedTotalAssetsSommelier1=$(cast call $SOMMELIER_ST_ETH_STRATEGY "estimatedTotalAssets()(uint256)")
estimatedTotalAssetsSommelier2=$(cast call $SOMMELIER_ST_ETH_DEPOSIT_ST_ETH_STRATEGY "estimatedTotalAssets()(uint256)")

# 2.5.- [4eStrategy] getStrategyTotalDebt
getStrategyTotalDebtYearn=$(cast call $VAULT "getStrategyTotalDebt(address)(uint256)" $YEARN_STRATEGY)
getStrategyTotalDebtConvex=$(cast call $VAULT "getStrategyTotalDebt(address)(uint256)" $CONVEX_STRATEGY)
getStrategyTotalDebtSommelier1=$(cast call $VAULT "getStrategyTotalDebt(address)(uint256)" $SOMMELIER_ST_ETH_STRATEGY)
getStrategyTotalDebtSommelier2=$(cast call $VAULT "getStrategyTotalDebt(address)(uint256)" $SOMMELIER_ST_ETH_DEPOSIT_ST_ETH_STRATEGY)

# 4.- [4eStrategy] unharvestedAmount
unharvestedAmountYearn=$(cast call $YEARN_STRATEGY "unharvestedAmount()(int256)" | awk '{print $1}')
unharvestedAmountConvex=$(cast call $CONVEX_STRATEGY "unharvestedAmount()(int256)" | awk '{print $1}')
unharvestedAmountSommelier1=$(cast call $SOMMELIER_ST_ETH_STRATEGY "unharvestedAmount()(int256)" | awk '{print $1}')
unharvestedAmountSommelier2=$(cast call $SOMMELIER_ST_ETH_DEPOSIT_ST_ETH_STRATEGY "unharvestedAmount()(int256)" | awk '{print $1}')

# 3.- [Vault] totalAssets
totalAssets=$(cast call $VAULT "totalAssets()(uint256)")

# 3.5.- [Vault] totalAccountedAssets
totalAccountedAssets=$(cast call $VAULT "totalDeposits()(uint256)")

# 4.- [Vault] balanceOf(user)
balanceUser=$(cast call $VAULT "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS)

# 5.- [Vault] convertToAssets(#4: shares_user)
convertToAssets=$(cast call $VAULT "convertToAssets(uint256)(uint256)" $balanceUser)

# 6.- [Vault] previewRedeem(#4: shares_user)
previewRedeem=$(cast call $VAULT "previewRedeem(uint256)(uint256)" $balanceUser)

# 7.- [Vault] totalIdle
totalIdle=$(cast call $VAULT "totalIdle()(uint256)")

# 8.- [Vault] totalDebt
totalDebt=$(cast call $VAULT "totalDebt()(uint256)")

echo ""
echo "[VAULT] sharePrice:" $sharePrice
echo "----------------------------------------------------------------"
echo "[YSTRAT] Total Assets: (rewards included)" $estimatedTotalAssetsYearn
echo "[YSTRAT] Principal:" $getStrategyTotalDebtYearn
echo "[YSTRAT] unharvestedAmount:" $unharvestedAmountYearn
echo "----------------------------------------------------------------"
echo "[CSTRAT] Total Assets: (rewards included)" $estimatedTotalAssetsConvex
echo "[CSTRAT] Principal:" $getStrategyTotalDebtConvex
echo "[CSTRAT] unharvestedAmount:" $unharvestedAmountConvex
echo "----------------------------------------------------------------"
echo "[SSTRAT1] Total Assets: (rewards included)" $estimatedTotalAssetsSommelier1
echo "[SSTRAT1] Principal:" $getStrategyTotalDebtSommelier1
echo "[SSTRAT1] unharvestedAmount:" $unharvestedAmountSommelier1
echo "----------------------------------------------------------------"
echo "[SSTRAT2] Total Assets: (rewards included)" $estimatedTotalAssetsSommelier2
echo "[SSTRAT2] Principal:" $getStrategyTotalDebtSommelier2
echo "[SSTRAT2] unharvestedAmount: $unharvestedAmountSommelier2"
echo "----------------------------------------------------------------"
echo "[VAULT] totalIdle:" $totalIdle
echo "[VAULT] totalDebt:" $totalDebt
echo "[VAULT] totalDeposits:" $totalAccountedAssets
echo "----------------------------------------------------------------"
echo "[VAULT] totalAssets (rewards included):" $totalAssets
echo "[VAULT] balanceOf(user) (shares):" $balanceUser
echo "[VAULT] convertToAssets:" $convertToAssets
echo "[VAULT] previewRedeem:" $previewRedeem
echo ""
