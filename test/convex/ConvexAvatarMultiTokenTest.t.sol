// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20MetadataUpgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {ConvexAvatarMultiToken, TokenAmount} from "../../src/convex/ConvexAvatarMultiToken.sol";
import {ConvexAvatarUtils} from "../../src/convex/ConvexAvatarUtils.sol";
import {MAX_BPS, CHAINLINK_KEEPER_REGISTRY} from "../../src/BaseConstants.sol";

import {IBaseRewardPool} from "../../src/interfaces/aura/IBaseRewardPool.sol";
import {IStakingProxy} from "../../src/interfaces/convex/IStakingProxy.sol";
import {IFraxUnifiedFarm} from "../../src/interfaces/convex/IFraxUnifiedFarm.sol";
import {IAggregatorV3} from "../../src/interfaces/chainlink/IAggregatorV3.sol";

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract ConvexAvatarMultiTokenTest is Test, ConvexAvatarUtils {
    ConvexAvatarMultiToken avatar;

    // Convex
    uint256 constant CONVEX_PID_BADGER_WBTC = 74;
    uint256 constant CONVEX_PID_BADGER_FRAXBP = 35;

    IERC20MetadataUpgradeable constant CURVE_LP_BADGER_WBTC =
        IERC20MetadataUpgradeable(0x137469B55D1f15651BA46A89D0588e97dD0B6562);
    IERC20MetadataUpgradeable constant CURVE_LP_BADGER_FRAXBP =
        IERC20MetadataUpgradeable(0x09b2E090531228d1b8E3d948C73b990Cb6e60720);
    IERC20MetadataUpgradeable constant WCVX_BADGER_FRAXBP =
        IERC20MetadataUpgradeable(0xb92e3fD365Fc5E038aa304Afe919FeE158359C88);

    IBaseRewardPool constant BASE_REWARD_POOL_BADGER_WBTC = IBaseRewardPool(0x36c7E7F9031647A74687ce46A8e16BcEA84f3865);
    IFraxUnifiedFarm constant UNIFIED_FARM_BADGER_FRAXBP = IFraxUnifiedFarm(0x5a92EF27f4baA7C766aee6d751f754EBdEBd9fae);

    address constant owner = address(1);
    address constant manager = address(2);
    address constant keeper = CHAINLINK_KEEPER_REGISTRY;

    address[2] assetsExpected = [address(CURVE_LP_BADGER_WBTC), address(WCVX_BADGER_FRAXBP)];

    ////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////

    event ManagerUpdated(address indexed oldManager, address indexed newManager);
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);

    event ClaimFrequencyUpdated(uint256 oldClaimFrequency, uint256 newClaimFrequency);

    event MinOutBpsCrvToWethValUpdated(uint256 newValue, uint256 oldValue);
    event MinOutBpsCvxToWethValUpdated(uint256 newValue, uint256 oldValue);
    event MinOutBpsFxsToFraxValUpdated(uint256 newValue, uint256 oldValue);
    event MinOutBpsWethToUsdcValUpdated(uint256 newValue, uint256 oldValue);

    event Deposit(address indexed token, uint256 amount, uint256 timestamp);
    event Withdraw(address indexed token, uint256 amount, uint256 timestamp);

    event RewardClaimed(address indexed token, uint256 amount, uint256 timestamp);
    event RewardsToStable(address indexed token, uint256 amount, uint256 timestamp);

    function setUp() public {
        // NOTE: pin a block where all required contracts already has being deployed
        vm.createSelectFork("mainnet", 16084000);

        // Labels
        vm.label(address(FXS), "FXS");
        vm.label(address(CRV), "CRV");
        vm.label(address(CVX), "CVX");
        vm.label(address(DAI), "DAI");
        vm.label(address(FRAX), "FRAX");
        vm.label(address(WETH), "WETH");

        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;

        uint256[] memory pidsFraxInit = new uint256[](1);
        pidsFraxInit[0] = CONVEX_PID_BADGER_FRAXBP;

        avatar = new ConvexAvatarMultiToken();
        avatar.initialize(owner, manager, pidsInit, pidsFraxInit);

        for (uint256 i = 0; i < assetsExpected.length; i++) {
            deal(assetsExpected[i], owner, 20e18, true);
        }

        vm.startPrank(owner);
        CURVE_LP_BADGER_WBTC.approve(address(avatar), 20e18);
        WCVX_BADGER_FRAXBP.approve(address(avatar), 20e18);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////
    function test_initialize() public {
        assertEq(avatar.owner(), owner);
        assertFalse(avatar.paused());

        assertEq(avatar.manager(), manager);

        uint256 bpsVal;
        uint256 bpsMin;

        (bpsVal, bpsMin) = avatar.minOutBpsCrvToWeth();
        assertEq(bpsVal, 9850);
        assertEq(bpsMin, 9500);

        (bpsVal, bpsMin) = avatar.minOutBpsCvxToWeth();
        assertEq(bpsVal, 9850);
        assertEq(bpsMin, 9500);

        (bpsVal, bpsMin) = avatar.minOutBpsFxsToFrax();
        assertEq(bpsVal, 9850);
        assertEq(bpsMin, 9500);

        (bpsVal, bpsMin) = avatar.minOutBpsWethToUsdc();
        assertEq(bpsVal, 9850);
        assertEq(bpsMin, 9500);

        (bpsVal, bpsMin) = avatar.minOutBpsFraxToDai();
        assertEq(bpsVal, 9850);
        assertEq(bpsMin, 9500);
    }

    function test_initialize_double() public {
        vm.expectRevert("Initializable: contract is already initialized");
        uint256[] memory pids;
        uint256[] memory fraxPids;
        avatar.initialize(address(this), address(this), pids, fraxPids);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Ownership
    ////////////////////////////////////////////////////////////////////////////

    function test_transferOwnership() public {
        vm.prank(owner);
        avatar.transferOwnership(address(this));

        assertEq(avatar.owner(), address(this));
    }

    function test_transferOwnership_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.transferOwnership(address(this));
    }

    ////////////////////////////////////////////////////////////////////////////
    // Pausing
    ////////////////////////////////////////////////////////////////////////////

    function test_pause() public {
        address[2] memory actors = [owner, manager];
        for (uint256 i; i < actors.length; ++i) {
            uint256 snapId = vm.snapshot();

            vm.prank(actors[i]);
            avatar.pause();

            assertTrue(avatar.paused());

            // Test pausable action to ensure modifier works
            vm.startPrank(keeper);

            vm.expectRevert("Pausable: paused");
            avatar.performUpkeep(new bytes(0));

            vm.stopPrank();

            vm.revertTo(snapId);
        }
    }

    function test_pause_permissions() public {
        vm.expectRevert(abi.encodeWithSelector(ConvexAvatarMultiToken.NotOwnerOrManager.selector, (address(this))));
        avatar.pause();
    }

    function test_unpause() public {
        vm.startPrank(owner);
        avatar.pause();

        assertTrue(avatar.paused());

        avatar.unpause();
        assertFalse(avatar.paused());
    }

    function test_unpause_permissions() public {
        vm.prank(owner);
        avatar.pause();

        address[2] memory actors = [address(this), manager];
        for (uint256 i; i < actors.length; ++i) {
            uint256 snapId = vm.snapshot();

            vm.expectRevert("Ownable: caller is not the owner");
            vm.prank(actors[i]);
            avatar.unpause();

            vm.revertTo(snapId);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    // Config: Owner
    ////////////////////////////////////////////////////////////////////////////

    function test_setManager() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ManagerUpdated(address(this), manager);
        avatar.setManager(address(this));

        assertEq(avatar.manager(), address(this));
    }

    function test_setManager_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.setManager(address(0));
    }

    function test_setClaimFrequency() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit ClaimFrequencyUpdated(2 weeks, 1 weeks);
        avatar.setClaimFrequency(2 weeks);

        assertEq(avatar.claimFrequency(), 2 weeks);
    }

    function test_setClaimFrequency_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.setClaimFrequency(2 weeks);
    }

    function test_addCurveLp_position_info_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.addCurveLpPositionInfo(21);
    }

    function test_addCurveLp_position_infopt() public {
        vm.prank(owner);
        avatar.addCurveLpPositionInfo(21);

        uint256[] memory avatarPids = avatar.getPids();
        bool pidIsAdded;

        for (uint256 i = 0; i < avatarPids.length; i++) {
            if (avatarPids[i] == 21) {
                pidIsAdded = true;
            }
        }

        assertTrue(pidIsAdded);
    }

    function test_removeCurveLp_position_info_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.removeCurveLpPositionInfo(21);
    }

    function test_removeCurveLp_position_info_non_existent() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ConvexAvatarMultiToken.PidNotIncluded.selector, 120));
        avatar.removeCurveLpPositionInfo(120);
    }

    function test_removeCurveLp_position_info_still_staked() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConvexAvatarMultiToken.CurveLpStillStaked.selector,
                address(CURVE_LP_BADGER_WBTC),
                address(BASE_REWARD_POOL_BADGER_WBTC),
                20 ether
            )
        );
        vm.prank(owner);
        avatar.removeCurveLpPositionInfo(CONVEX_PID_BADGER_WBTC);
    }

    function test_removeCurveLp_position_info() public {
        vm.prank(owner);
        avatar.removeCurveLpPositionInfo(CONVEX_PID_BADGER_WBTC);

        uint256[] memory avatarPids = avatar.getPids();

        bool pidIsPresent;

        for (uint256 i = 0; i < avatarPids.length; i++) {
            if (avatarPids[i] == CONVEX_PID_BADGER_WBTC) {
                pidIsPresent = true;
            }
        }

        assertFalse(pidIsPresent);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Config: Manager/Owner
    ////////////////////////////////////////////////////////////////////////////

    function test_setMinOutBpsCrvToWethVal() external {
        uint256 val;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MinOutBpsCrvToWethValUpdated(9600, 9850);
        avatar.setMinOutBpsCrvToWethVal(9600);
        (val,) = avatar.minOutBpsCrvToWeth();
        assertEq(val, 9600);

        vm.prank(manager);
        avatar.setMinOutBpsCrvToWethVal(9820);
        (val,) = avatar.minOutBpsCrvToWeth();
        assertEq(val, 9820);
    }

    function test_setMinOutBpsCrvToWethVal_invalidValues() external {
        vm.startPrank(owner);
        avatar.setMinOutBpsCrvToWethVal(9700);

        vm.expectRevert(abi.encodeWithSelector(ConvexAvatarMultiToken.InvalidBps.selector, 60000));
        avatar.setMinOutBpsCrvToWethVal(60000);

        vm.expectRevert(abi.encodeWithSelector(ConvexAvatarMultiToken.LessThanBpsMin.selector, 1000, 9500));
        avatar.setMinOutBpsCrvToWethVal(1000);
    }

    function test_setMinOutBpsCrvToWethVal_permissions() external {
        vm.expectRevert(abi.encodeWithSelector(ConvexAvatarMultiToken.NotOwnerOrManager.selector, (address(this))));
        avatar.setMinOutBpsCrvToWethVal(9600);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Actions: Owner
    ////////////////////////////////////////////////////////////////////////////

    function test_deposit() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(CURVE_LP_BADGER_WBTC), 20 ether, block.timestamp);
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        assertEq(CURVE_LP_BADGER_WBTC.balanceOf(owner), 0);
        assertEq(BASE_REWARD_POOL_BADGER_WBTC.balanceOf(address(avatar)), 20e18);
    }

    function test_deposit_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        avatar.deposit(pidsInit, amountsDeposit);
    }

    function test_deposit_empty() public {
        vm.expectRevert(ConvexAvatarMultiToken.NothingToDeposit.selector);
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](1);
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        avatar.deposit(pidsInit, amountsDeposit);
    }

    function test_deposit_pid_not_in_storage() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = 120;
        vm.expectRevert(abi.encodeWithSelector(ConvexAvatarMultiToken.PidNotIncluded.selector, 120));
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);
    }

    function test_depositPrivateVault() public {
        uint256 amountToLock = 20 ether;
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(WCVX_BADGER_FRAXBP), amountToLock, block.timestamp);
        bytes32 kekId = avatar.depositInPrivateVault(CONVEX_PID_BADGER_FRAXBP, amountToLock);

        address vaultAddr = avatar.privateVaults(CONVEX_PID_BADGER_FRAXBP);
        IStakingProxy proxy = IStakingProxy(vaultAddr);

        uint256 lockedBal = IFraxUnifiedFarm(proxy.stakingAddress()).lockedLiquidityOf(vaultAddr);

        assertEq(lockedBal, amountToLock);
        assertEq(WCVX_BADGER_FRAXBP.balanceOf(owner), 0);
        assertEq(kekId, avatar.kekIds(vaultAddr));
    }

    function test_depositPrivateVault_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.depositInPrivateVault(CONVEX_PID_BADGER_FRAXBP, 20 ether);
    }

    function test_depositPrivateVault_empty() public {
        vm.expectRevert(ConvexAvatarMultiToken.NothingToDeposit.selector);
        vm.prank(owner);
        avatar.depositInPrivateVault(CONVEX_PID_BADGER_FRAXBP, 0);
    }

    function test_withdrawAll() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(CURVE_LP_BADGER_WBTC), 20 ether, block.timestamp);
        avatar.withdrawAll();

        assertEq(BASE_REWARD_POOL_BADGER_WBTC.balanceOf(address(avatar)), 0);
        assertEq(CURVE_LP_BADGER_WBTC.balanceOf(owner), 20e18);
    }

    function test_withdrawAll_nothing() public {
        vm.expectRevert(ConvexAvatarMultiToken.NothingToWithdraw.selector);
        vm.prank(owner);
        avatar.withdrawAll();
    }

    function test_withdrawAll_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.withdrawAll();
    }

    function test_withdraw() public {
        vm.startPrank(owner);
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        avatar.deposit(pidsInit, amountsDeposit);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(CURVE_LP_BADGER_WBTC), 10e18, block.timestamp);
        uint256[] memory amountsWithdraw = new uint256[](1);
        amountsWithdraw[0] = 10 ether;
        avatar.withdraw(pidsInit, amountsWithdraw);

        assertEq(BASE_REWARD_POOL_BADGER_WBTC.balanceOf(address(avatar)), 10e18);
        assertEq(CURVE_LP_BADGER_WBTC.balanceOf(owner), 10e18);
    }

    function test_withdraw_nothing() public {
        uint256[] memory amountsWithdraw = new uint256[](1);
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.expectRevert(ConvexAvatarMultiToken.NothingToWithdraw.selector);
        vm.prank(owner);
        avatar.withdraw(pidsInit, amountsWithdraw);
    }

    function test_withdraw_permissions() public {
        uint256[] memory amountsWithdraw = new uint256[](1);
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.withdraw(pidsInit, amountsWithdraw);
    }

    function test_withdrawFromPrivateVault() public {
        vm.prank(owner);
        avatar.depositInPrivateVault(CONVEX_PID_BADGER_FRAXBP, 20 ether);

        skip(2 weeks);

        vm.prank(owner);
        avatar.withdrawFromPrivateVault(CONVEX_PID_BADGER_FRAXBP);

        address vaultAddr = avatar.privateVaults(CONVEX_PID_BADGER_FRAXBP);
        IStakingProxy proxy = IStakingProxy(vaultAddr);

        assertEq(IFraxUnifiedFarm(proxy.stakingAddress()).lockedLiquidityOf(vaultAddr), 0);

        assertEq(CURVE_LP_BADGER_FRAXBP.balanceOf(owner), 20e18);
    }

    function test_withdrawFromPrivateVault_nothing() public {
        vm.expectRevert(ConvexAvatarMultiToken.NothingToWithdraw.selector);
        vm.prank(owner);
        avatar.withdrawFromPrivateVault(CONVEX_PID_BADGER_FRAXBP);
    }

    function test_withdrawFromPrivateVault_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.withdrawFromPrivateVault(CONVEX_PID_BADGER_FRAXBP);
    }

    function test_claimRewardsAndSendToOwner() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        uint256 initialOwnerCrv = CRV.balanceOf(owner);
        uint256 initialOwnerCvx = CVX.balanceOf(owner);

        skip(1 hours);

        uint256 crvReward = BASE_REWARD_POOL_BADGER_WBTC.earned(address(avatar));

        assertGt(crvReward, 0);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(address(CRV), crvReward, block.timestamp);
        avatar.claimRewardsAndSendToOwner();

        assertEq(BASE_REWARD_POOL_BADGER_WBTC.earned(address(avatar)), 0);

        assertEq(CRV.balanceOf(address(avatar)), 0);
        assertEq(CVX.balanceOf(address(avatar)), 0);

        assertGt(CRV.balanceOf(owner), initialOwnerCrv);
        assertGt(CVX.balanceOf(owner), initialOwnerCvx);
    }

    function test_claimRewardsAndSendToOwner_permissions() public {
        address[2] memory actors = [address(this), manager];
        for (uint256 i; i < actors.length; ++i) {
            uint256 snapId = vm.snapshot();

            vm.expectRevert("Ownable: caller is not the owner");
            vm.prank(actors[i]);
            avatar.claimRewardsAndSendToOwner();

            vm.revertTo(snapId);
        }
    }

    function test_claimRewardsAndSendToOwner_noRewards() public {
        vm.expectRevert(ConvexAvatarMultiToken.NoRewards.selector);
        vm.prank(owner);
        avatar.claimRewardsAndSendToOwner();
    }

    ////////////////////////////////////////////////////////////////////////////
    // Actions: Keeper
    ////////////////////////////////////////////////////////////////////////////

    function test_checkUpKeep() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        skip(1 weeks);

        (bool upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertTrue(upkeepNeeded);
    }

    function test_performUpKeep() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = CONVEX_PID_BADGER_WBTC;
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);
        vm.prank(owner);
        avatar.depositInPrivateVault(CONVEX_PID_BADGER_FRAXBP, 20 ether);

        skipAndForwardFeeds(1 weeks);

        uint256 daiBalanceBefore = DAI.balanceOf(owner);

        bool upkeepNeeded;
        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertTrue(upkeepNeeded);

        address privateVault = avatar.privateVaults(CONVEX_PID_BADGER_FRAXBP);

        vm.prank(keeper);
        vm.expectEmit(true, false, false, false);
        emit RewardsToStable(address(DAI), 0, block.timestamp);
        avatar.performUpkeep(new bytes(0));

        // Ensure that rewards were processed properly
        assertEq(BASE_REWARD_POOL_BADGER_WBTC.earned(address(avatar)), 0);
        uint256[] memory accruedRewards = UNIFIED_FARM_BADGER_FRAXBP.earned(privateVault);
        for (uint256 i; i < accruedRewards.length; i++) {
            assertEq(accruedRewards[i], 0);
        }

        // DAI balance increased on owner
        assertGt(DAI.balanceOf(owner), daiBalanceBefore);

        // Upkeep is not needed anymore
        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertFalse(upkeepNeeded);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Internal helpers
    ////////////////////////////////////////////////////////////////////////////

    function skipAndForwardFeeds(uint256 _duration) internal {
        skip(_duration);
        forwardClFeed(FXS_USD_FEED, _duration);
        forwardClFeed(CRV_ETH_FEED, _duration);
        forwardClFeed(CVX_ETH_FEED, _duration);
        forwardClFeed(DAI_ETH_FEED, _duration);
        forwardClFeed(FRAX_USD_FEED, _duration);
        forwardClFeed(DAI_USD_FEED, _duration);
    }

    function forwardClFeed(IAggregatorV3 _feed, uint256 _duration) internal {
        int256 lastAnswer = _feed.latestAnswer();
        uint256 lastTimestamp = _feed.latestTimestamp();
        vm.etch(address(_feed), type(MockV3Aggregator).runtimeCode);
        MockV3Aggregator(address(_feed)).updateAnswerAndTimestamp(lastAnswer, lastTimestamp + _duration);
    }
}
