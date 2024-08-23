#!/bin/bash
source .env.strategies

# 1.- Share price
sharePrice=$(cast call $MAX_APY_VAULT "sharePrice()(uint256)")

query_strategy(){
    local strategy_name=$1
    local strategy_address=$2

    # 2.- [4eStrategy] estimatedTotalAssets
    local estimated_total_assets=$(cast call $strategy_address "estimatedTotalAssets()(uint256)")
    local strategy_total_debt=$(cast call $MAX_APY_VAULT "getStrategyTotalDebt(address)(uint256)" $strategy_address)
    local unharvested_amount=$(cast call $strategy_address "unharvestedAmount()(int256)" | awk '{print $1}')
    local debtRatio=$(cast call $MAX_APY_VAULT "strategies(address)(uint16,uint16,uint48,uint48,uint128,uint128,uint128,uint128,uint128,bool)" $strategy_address | head -n 1)

    echo "--------------------------------------------------------------------------------------------"
    echo "[$strategy_name] Total Assets: (rewards included)" $estimated_total_assets
    echo "[$strategy_name] Principal:" $strategy_total_debt
    echo "[$strategy_name] unharvestedAmount:" $unharvested_amount
    echo "[$strategy_name] debtRatio:" $debtRatio
}

for var in $(compgen -v); do
    if [[ $var == *_STRATEGY ]]; then
        strategy_name=${var}
        strategy_address=${!var}
        query_strategy $strategy_name $strategy_address
    fi
done

source .env
# 3.- [MAX_APY_VAULT] totalAssets
totalAssets=$(cast call $MAX_APY_VAULT "totalAssets()(uint256)")

# 3.5.- [MAX_APY_VAULT] totalAccountedAssets
totalAccountedAssets=$(cast call $MAX_APY_VAULT "totalDeposits()(uint256)")

# 4.- [MAX_APY_VAULT] balanceOf(user)
balanceUser=$(cast call $MAX_APY_VAULT "balanceOf(address)(uint256)" $DEPLOYER_ADDRESS)

# 5.- [MAX_APY_VAULT] convertToAssets(#4: shares_user)
convertToAssets=$(cast call $MAX_APY_VAULT "convertToAssets(uint256)(uint256)" $balanceUser)

# 6.- [MAX_APY_VAULT] previewRedeem(#4: shares_user)
previewRedeem=$(cast call $MAX_APY_VAULT "previewRedeem(uint256)(uint256)" $balanceUser)

# 7.- [MAX_APY_VAULT] totalIdle
totalIdle=$(cast call $MAX_APY_VAULT "totalIdle()(uint256)")

# 8.- [MAX_APY_VAULT] totalDebt
totalDebt=$(cast call $MAX_APY_VAULT "totalDebt()(uint256)")

echo ""
echo "[MAX_APY_VAULT] sharePrice:" $sharePrice
echo "--------------------------------------------------------------------------------------------"
echo "[MAX_APY_VAULT] totalIdle:" $totalIdle
echo "[MAX_APY_VAULT] totalDebt:" $totalDebt
echo "[MAX_APY_VAULT] totalDeposits:" $totalAccountedAssets
echo "--------------------------------------------------------------------------------------------"
echo "[MAX_APY_VAULT] totalAssets (rewards included):" $totalAssets
echo "[MAX_APY_VAULT] balanceOf(user) (shares):" $balanceUser
echo "[MAX_APY_VAULT] convertToAssets:" $convertToAssets
echo "[MAX_APY_VAULT] previewRedeem:" $previewRedeem
echo ""