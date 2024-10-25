// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.19;

//////////////////////////////// MAINNET ////////////////////////////////
// Tokens
address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant STETH_MAINNET = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address constant LUSD_MAINNET = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
address constant CRV_MAINNET = 0xD533a949740bb3306d119CC777fa900bA034cd52;
address constant CVX_MAINNET = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
address constant CRVUSD_MAINNET = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
address constant FRXETH_MAINNET = 0x5E8422345238F34275888049021821E8E08CAa1f;
address constant AJNA_MAINNET = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
address constant WSTETH_MAINNET = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
address constant RETH_MAINNET = 0xae78736Cd615f374D3085123A210448E74Fc6393;
address constant ETHX_MAINNET = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
address constant GHO_MAINNET = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

// Main protocols contracts
address constant CONVEX_BOOSTER_MAINNET = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
address constant UNISWAP_V3_ROUTER_MAINNET = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address constant UNISWAP_V3_USDC_LUSD_POOL_MAINNET = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736;
address constant BALANCER_VAULT_MAINNET = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
address constant SUSHISWAP_ROUTER_MAINNET = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

// Strategy underlying
address constant SOMMELIER_MORPHO_ETH_MAXIMIZER_CELLAR_MAINNET = 0xcf4B531b4Cde95BD35d71926e09B2b54c564F5b6;
address constant SOMMELIER_ST_ETH_DEPOSIT_TURBO_STETH_CELLAR_MAINNET = 0xc7372Ab5dd315606dB799246E8aA112405abAeFf;
address constant SOMMELIER_TURBO_EETHV2_CELLAR_MAINNET = 0xdAdC82e26b3739750E036dFd9dEfd3eD459b877A;
address constant SOMMELIER_TURBO_EETHX_CELLAR_MAINNET = 0x19B8D8FC682fC56FbB42653F68c7d48Dd3fe597E;
address constant SOMMELIER_TURBO_EZETH_CELLAR_MAINNET = 0x27500De405a3212D57177A789E30bb88b0AdbeC5;
address constant SOMMELIER_TURBO_GHO_CELLAR_MAINNET = 0x0C190DEd9Be5f512Bd72827bdaD4003e9Cc7975C;
address constant SOMMELIER_TURBO_RSETH_CELLAR_MAINNET = 0x1dffb366b5c5A37A12af2C127F31e8e0ED86BDbe;
address constant SOMMELIER_TURBO_STETH_CELLAR_MAINNET = 0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971;
address constant SOMMELIER_TURBO_DIV_ETH_CELLAR_MAINNET = 0x6c1edce139291Af5b84fB1e496c9747F83E876c9;
address constant SOMMELIER_TURBO_SWETH_CELLAR_MAINNET = 0xd33dAd974b938744dAC81fE00ac67cb5AA13958E;
address constant YEARN_AAVEv3_WETH_LENDER_YVAULT_MAINNET = 0xd2eFB90C569eBD5b83D5cFB8632322edFAc203A5;
address constant YEARN_AJNA_DAI_STAKING_YVAULT_MAINNET = 0xe24BA27551aBE96Ca401D39761cA2319Ea14e3CB;
address constant YEARN_AJNA_WETH_STAKING_YVAULT_MAINNET = 0x503e0BaB6acDAE73eA7fb7cf6Ae5792014dbe935;
address constant YEARN_DAI_YVAULT_MAINNET = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;
address constant YEARN_LUSD_YVAULT_MAINNET = 0x378cb52b00F9D0921cb46dFc099CFf73b42419dC;
address constant YEARN_USDC_YVAULT_MAINNET = 0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE;
address constant YEARN_WETH_YVAULT_MAINNET = 0xa258C4606Ca8206D8aA700cE2143D7db854D168c;
address constant YEARN_USDT_YVAULT_MAINNET = 0x3B27F92C0e212C671EA351827EDF93DB27cc0c65;
address constant YEARN_COMPOUND_V3_WETH_LENDER_YVAULT_MAINNET = 0x23eE3D14F09946A084350CC6A7153fc6eb918817;
address constant YEARNV3_WETH_YVAULT_MAINNET = 0xc56413869c6CDf96496f2b1eF801fEDBdFA7dDB0;
address constant YEARNV3_WETH2_YVAULT_MAINNET = 0xAc37729B76db6438CE62042AE1270ee574CA7571;
address constant CURVE_CRVUSD_WETH_COLLATERAL_LENDING_POOL_MAINNET = 0x5AE28c9197a4a6570216fC7e53E7e0221D7A0FEF;
address constant CURVE_USDC_CRVUSD_POOL_MAINNET = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
address constant CURVE_DETH_FRXETH_POOL_MAINNET = 0x7C0d189E1FecB124487226dCbA3748bD758F98E4;
address constant CURVE_ETH_FRXETH_POOL_MAINNET = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
address constant CURVE_ETH_STETH_POOL_MAINNET = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
address constant CURVE_ETHX_WETH_POOL_MAINNET = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
address constant CURVE_CVX_WETH_POOL_MAINNET = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
address constant CURVE_3POOL_POOL_MAINNET = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
uint256 constant CONVEX_CRVUSD_WETH_COLLATERAL_POOL_ID_MAINNET = 326;
uint256 constant CONVEX_DETH_FRXETH_CONVEX_POOL_ID_MAINNET = 195;

//////////////////////////////// POLYGON ////////////////////////////////
// Tokens
address constant USDT_POLYGON = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
address constant CRV_USD_POLYGON = 0xc4Ce1D6F5D98D65eE25Cf85e9F2E9DcFEe6Cb5d6;
address constant DAI_POLYGON = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
address constant USDCE_POLYGON = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
address constant CRV_POLYGON = 0x172370d5Cd63279eFa6d502DAB29171933a610AF;
address constant WPOL_POLYGON = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
address constant AJNA_POLYGON = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
address constant USDC_POLYGON = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

// Main protocol contracts
address constant CONVEX_BOOSTER_POLYGON = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
address constant UNISWAP_V3_ROUTER_POLYGON = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
address constant ALGEBRA_POOL = 0xe7E0eB9F6bCcCfe847fDf62a3628319a092F11a2;

// Strategy underlying
address constant UNISWAP_V3_USDC_USDCE_POOL_POLYGON = 0xD36ec33c8bed5a9F7B6630855f1533455b98a418;
address constant CURVE_CRVUSD_USDC_POOL_POLYGON = 0x5225010A0AE133B357861782B0B865a48471b2C5;
address constant CURVE_AAVE_ATRICRYPTO_ZAPPER_POLYGON = 0x1d8b86e3D88cDb2d34688e87E72F388Cb541B7C8;
address constant CURVE_CRV_ATRICRYPTO_ZAPPER_POLYGON = 0x3d8EADb739D1Ef95dd53D718e4810721837c69c1;
address constant YEARN_USDCE_LENDER_YVAULT_POLYGON = 0xdB92B89Ca415c0dab40Dc96E99Fc411C08F20780;
address constant YEARN_DAI_LENDER_YVAULT_POLYGON = 0xf4F9d5697341B4C9B0Cc8151413e05A90f7dc24F;
address constant YEARN_MATIC_USDC_STAKING_YVAULT_POLYGON = 0xF54a15F6da443041Bb075959EA66EE47655DDFcA;
address constant YEARN_COMPOUND_USDC_LENDER_YVAULT_POLYGON = 0xb1403908F772E4374BB151F7C67E88761a0Eb4f1;
address constant YEARN_AJNA_USDC_YVAULT_POLYGON = 0xF54a15F6da443041Bb075959EA66EE47655DDFcA;
address constant YEARN_DAI_YVAULT_POLYGON = 0x90b2f54C6aDDAD41b8f6c4fCCd555197BC0F773B;
address constant YEARN_USDCE_YVAULT_POLYGON = 0xA013Fbd4b711f9ded6fB09C1c0d358E2FbC2EAA0;
address constant YEARN_USDT_YVAULT_POLYGON = 0xBb287E6017d3DEb0e2E65061e8684eab21060123;
uint256 constant CRVUSD_USDT_CONVEX_POOL_ID_POLYGON = 14;
uint256 constant CRVUSD_USDC_CONVEX_POOL_ID_POLYGON = 13;
address constant CURVE_MAI_USDCE_POOL_POLYGON = 0x53C38755748745e2dd7D0a136FBCC9fB1A5B83b2;
address constant BEEFY_MAI_USDCE_POLYGON = 0x378FcE425239B0c6B43eF79E773794dd2e9979AD;
address constant YEARN_AAVE_V3_USDT_LENDER_YVAULT_POLYGON = 0x3bd8C987286D8Ad00c05fdb2Ae3E8C9a0f054734;
address constant TRI_CRYPTO_POOL_POLYGON = 0xc7c939A474CB10EB837894D1ed1a77C61B268Fa7;
address constant CURVE_CRVUSD_USDCE_POOL_POLYGON = 0x864490Cf55dc2Dee3f0ca4D06F5f80b2BB154a03;
address constant BEEFY_CRVUSD_USDCE_POLYGON = 0xb6D78A6eDa4318067183C4A5076E25197f4e5009;
address constant CURVE_CRVUSD_USDT_POOL_POLYGON = 0xA70Af99bFF6b168327f9D1480e29173e757c7904;
address constant BEEFY_USDCE_DAI_POLYGON = 0x3A1F8B9b4aB6ba1a845931eD527B6B4768Ca07B1;
address constant GAMMA_USDCE_DAI_UNIPROXY_POLYGON = 0xA42d55074869491D60Ac05490376B74cF19B00e6;
address constant GAMMA_USDCE_DAI_HYPERVISOR_POLYGON = 0x9E31214Db6931727B7d63a0D2b6236DB455c0965;
