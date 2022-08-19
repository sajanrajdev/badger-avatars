// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC20Upgradeable.sol";

import {IAuraLocker} from "../../interfaces/aura/IAuraLocker.sol";
import {IAuraToken} from "../../interfaces/aura/IAuraToken.sol";
import {IBaseRewardPool} from "../../interfaces/aura/IBaseRewardPool.sol";
import {IBooster} from "../../interfaces/aura/IBooster.sol";
import {ICrvDepositorWrapper} from "../../interfaces/aura/ICrvDepositorWrapper.sol";
import {IVault} from "../../interfaces/badger/IVault.sol";
import {IBalancerVault} from "../../interfaces/balancer/IBalancerVault.sol";
import {IPriceOracle} from "../../interfaces/balancer/IPriceOracle.sol";
import {IAggregatorV3} from "../../interfaces/chainlink/IAggregatorV3.sol";

abstract contract AuraConstants {
    ////////////////////////////////////////////////////////////////////////////
    // CONSTANTS
    ////////////////////////////////////////////////////////////////////////////

    IBalancerVault internal constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IBooster internal constant AURA_BOOSTER = IBooster(0x7818A1DA7BD1E64c199029E86Ba244a9798eEE10);
    IAuraLocker internal constant AURA_LOCKER = IAuraLocker(0x3Fa73f1E5d8A792C80F426fc8F84FBF7Ce9bBCAC);
    ICrvDepositorWrapper internal constant AURABAL_DEPOSIT_WRAPPER =
        ICrvDepositorWrapper(0x68655AD9852a99C87C0934c7290BB62CFa5D4123);
    IBaseRewardPool internal constant AURABAL_REWARDS = IBaseRewardPool(0x5e5ea2048475854a5702F5B8468A51Ba1296EFcC);

    IVault internal constant BAURABAL = IVault(0x37d9D2C6035b744849C15F1BFEE8F268a20fCBd8);
    address internal constant BADGER_VOTER = address(0xA9ed98B5Fb8428d68664f3C5027c62A10d45826b);

    IAuraToken internal constant AURA = IAuraToken(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    IERC20Upgradeable internal constant BAL = IERC20Upgradeable(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20Upgradeable internal constant WETH = IERC20Upgradeable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20Upgradeable internal constant USDC = IERC20Upgradeable(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20Upgradeable internal constant AURABAL = IERC20Upgradeable(0x616e8BfA43F920657B3497DBf40D6b1A02D4608d);

    bytes32 internal constant BAL_WETH_POOL_ID = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
    bytes32 internal constant AURA_WETH_POOL_ID = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274; // 50AURA-20WETH
    bytes32 internal constant USDC_WETH_POOL_ID = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

    IAggregatorV3 internal constant BAL_USD_FEED = IAggregatorV3(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);
    IAggregatorV3 internal constant ETH_USD_FEED = IAggregatorV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    IPriceOracle internal constant POOL_80AURA_20WETH = IPriceOracle(0xc29562b045D80fD77c69Bec09541F5c16fe20d9d);

    uint256 internal constant USD_FEED_PRECISIONS = 1e8;
    uint256 internal constant AURA_WETH_TWAP_PRECISION = 1e18;
}