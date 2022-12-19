// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console2 as console} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20MetadataUpgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import {AuraAvatarMultiToken, TokenAmount} from "../../src/aura/AuraAvatarMultiToken.sol";
import {AuraAvatarUtils} from "../../src/aura/AuraAvatarUtils.sol";
import {
    MAX_BPS,
    PID_80BADGER_20WBTC,
    PID_40WBTC_40DIGG_20GRAVIAURA,
    PID_50BADGER_50RETH
} from "../../src/BaseConstants.sol";
import {AuraConstants} from "../../src/aura/AuraConstants.sol";
import {IAsset} from "../../src/interfaces/balancer/IAsset.sol";
import {IBalancerVault, JoinKind} from "../../src/interfaces/balancer/IBalancerVault.sol";
import {IPriceOracle} from "../../src/interfaces/balancer/IPriceOracle.sol";
import {IBaseRewardPool} from "../../src/interfaces/aura/IBaseRewardPool.sol";
import {IAggregatorV3} from "../../src/interfaces/chainlink/IAggregatorV3.sol";

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract AuraAvatarMultiTokenTest is Test, AuraAvatarUtils {
    AuraAvatarMultiToken avatar;

    IERC20MetadataUpgradeable constant BPT_80BADGER_20WBTC =
        IERC20MetadataUpgradeable(0xb460DAa847c45f1C4a41cb05BFB3b51c92e41B36);
    IERC20MetadataUpgradeable constant BPT_40WBTC_40DIGG_20GRAVIAURA =
        IERC20MetadataUpgradeable(0x8eB6c82C3081bBBd45DcAC5afA631aaC53478b7C);
    IERC20MetadataUpgradeable constant BPT_50BADGER_50RETH =
        IERC20MetadataUpgradeable(0xe340EBfcAA544da8bB1Ee9005F1a346D50Ec422e);

    IBaseRewardPool constant BASE_REWARD_POOL_80BADGER_20WBTC =
        IBaseRewardPool(0x05df1E87f41F793D9e03d341Cdc315b76595654C);
    IBaseRewardPool constant BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA =
        IBaseRewardPool(0xe86f0312b06126855810B4a13a43c3E2b1B8DD90);
    IBaseRewardPool constant BASE_REWARD_POOL_50BADGER_50RETH =
        IBaseRewardPool(0x685C94e7DA6C8F14Ae58f168C942Fb05bAD73412);

    address constant owner = address(1);
    address constant manager = address(2);
    address constant keeper = address(3);

    uint256[3] pidsExpected = [PID_80BADGER_20WBTC, PID_40WBTC_40DIGG_20GRAVIAURA, PID_50BADGER_50RETH];
    address[3] assetsExpected =
        [address(BPT_80BADGER_20WBTC), address(BPT_40WBTC_40DIGG_20GRAVIAURA), address(BPT_50BADGER_50RETH)];
    address[3] baseRewardsPoolExpected = [
        address(BASE_REWARD_POOL_80BADGER_20WBTC),
        address(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA),
        address(BASE_REWARD_POOL_50BADGER_50RETH)
    ];

    ////////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////////

    event ManagerUpdated(address indexed oldManager, address indexed newManager);
    event KeeperUpdated(address indexed oldKeeper, address indexed newKeeper);

    event TwapPeriodUpdated(uint256 newTwapPeriod, uint256 oldTwapPeriod);
    event ClaimFrequencyUpdated(uint256 oldClaimFrequency, uint256 newClaimFrequency);

    event MinOutBpsBalToUsdcMinUpdated(uint256 oldValue, uint256 newValue);
    event MinOutBpsAuraToUsdcMinUpdated(uint256 oldValue, uint256 newValue);
    event MinOutBpsBalToBptMinUpdated(uint256 oldValue, uint256 newValue);

    event MinOutBpsBalToUsdcValUpdated(uint256 oldValue, uint256 newValue);
    event MinOutBpsAuraToUsdcValUpdated(uint256 oldValue, uint256 newValue);
    event MinOutBpsBalToBptValUpdated(uint256 oldValue, uint256 newValue);

    event Deposit(address indexed token, uint256 amount, uint256 timestamp);
    event Withdraw(address indexed token, uint256 amount, uint256 timestamp);

    event RewardClaimed(address indexed token, uint256 amount, uint256 timestamp);
    event RewardsToStable(address indexed token, uint256 amount, uint256 timestamp);

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        // TODO: Remove hardcoded block
        vm.createSelectFork("mainnet", 15858000);

        // Labels
        vm.label(address(AURA), "AURA");
        vm.label(address(BAL), "BAL");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");

        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar = new AuraAvatarMultiToken();
        avatar.initialize(owner, manager, keeper, pidsInit);

        for (uint256 i = 0; i < assetsExpected.length; i++) {
            deal(assetsExpected[i], owner, 20e18, true);
        }

        vm.startPrank(owner);
        BPT_80BADGER_20WBTC.approve(address(avatar), 20e18);
        BPT_40WBTC_40DIGG_20GRAVIAURA.approve(address(avatar), 20e18);
        BPT_50BADGER_50RETH.approve(address(avatar), 20e18);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////

    function test_constructor() public {
        uint256[] memory pids = avatar.getPids();
        address[] memory assets = avatar.getAssets();
        address[] memory baseRewardPools = avatar.getbaseRewardPools();
        for (uint256 i = 0; i < pids.length; i++) {
            assertEq(pids[i], pidsExpected[i]);
            assertEq(assets[i], assetsExpected[i]);
            assertEq(baseRewardPools[i], baseRewardsPoolExpected[i]);
        }
    }

    function test_initialize() public {
        assertEq(avatar.owner(), owner);
        assertFalse(avatar.paused());

        assertEq(avatar.manager(), manager);
        assertEq(avatar.keeper(), keeper);

        uint256 bpsVal;
        uint256 bpsMin;

        (bpsVal, bpsMin) = avatar.minOutBpsBalToUsdc();
        assertEq(bpsVal, 9750);
        assertEq(bpsMin, 9000);

        (bpsVal, bpsMin) = avatar.minOutBpsAuraToUsdc();
        assertEq(bpsVal, 9750);
        assertEq(bpsMin, 9000);
    }

    function test_proxy_immutables() public {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        address logic = address(new AuraAvatarMultiToken());
        bytes memory initData = abi.encodeCall(AuraAvatarMultiToken.initialize, (owner, manager, keeper, pidsInit));
        AuraAvatarMultiToken avatarProxy = AuraAvatarMultiToken(
            address(
                new TransparentUpgradeableProxy(
                    logic,
                    address(proxyAdmin),
                    initData
                )
            )
        );

        uint256[] memory pids = avatarProxy.getPids();
        address[] memory assets = avatarProxy.getAssets();
        address[] memory baseRewardPools = avatarProxy.getbaseRewardPools();
        for (uint256 i = 0; i < pids.length; i++) {
            assertEq(pids[i], pidsExpected[i]);
            assertEq(assets[i], assetsExpected[i]);
            assertEq(baseRewardPools[i], baseRewardsPoolExpected[i]);
        }
    }

    function test_pendingRewards() public {
        (uint256 pendingBal, uint256 pendingAura) = avatar.pendingRewards();

        assertEq(pendingBal, BASE_REWARD_POOL_80BADGER_20WBTC.earned(address(avatar)));
        assertEq(pendingAura, BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.earned(address(avatar)));
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

            vm.expectRevert("Pausable: paused");
            avatar.processRewardsKeeper(0);

            vm.stopPrank();

            vm.revertTo(snapId);
        }
    }

    function test_pause_permissions() public {
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.NotOwnerOrManager.selector, (address(this))));
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

    function test_setKeeper() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit KeeperUpdated(address(this), keeper);
        avatar.setKeeper(address(this));

        assertEq(avatar.keeper(), address(this));
    }

    function test_setKeeper_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.setKeeper(address(0));
    }

    function test_setTwapPeriod() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit TwapPeriodUpdated(4 hours, 1 hours);
        avatar.setTwapPeriod(4 hours);

        assertEq(avatar.twapPeriod(), 4 hours);
    }

    function test_setTwapPeriod_zero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.ZeroTwapPeriod.selector));
        avatar.setTwapPeriod(0);
    }

    function test_setTwapPeriod_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.setTwapPeriod(2 weeks);
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

    function test_setMinOutBpsBalToUsdcMin() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MinOutBpsBalToUsdcMinUpdated(5000, 9000);
        avatar.setMinOutBpsBalToUsdcMin(5000);

        (, uint256 val) = avatar.minOutBpsBalToUsdc();
        assertEq(val, 5000);
    }

    function test_setMinOutBpsBalToUsdcMin_invalidValues() external {
        vm.startPrank(owner);
        avatar.setMinOutBpsBalToUsdcVal(9500);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.InvalidBps.selector, 1000000));
        avatar.setMinOutBpsBalToUsdcMin(1000000);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.MoreThanBpsVal.selector, 9600, 9500));
        avatar.setMinOutBpsBalToUsdcMin(9600);
    }

    function test_setMinOutBpsBalToUsdcMin_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.setMinOutBpsBalToUsdcMin(5000);
    }

    function test_setMinOutBpsAuraToUsdcMin() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MinOutBpsAuraToUsdcMinUpdated(5000, 9000);
        avatar.setMinOutBpsAuraToUsdcMin(5000);

        (, uint256 val) = avatar.minOutBpsAuraToUsdc();
        assertEq(val, 5000);
    }

    function test_setMinOutBpsAuraToUsdcMin_invalidValues() external {
        vm.startPrank(owner);
        avatar.setMinOutBpsAuraToUsdcVal(9500);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.InvalidBps.selector, 1000000));
        avatar.setMinOutBpsAuraToUsdcMin(1000000);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.MoreThanBpsVal.selector, 9600, 9500));
        avatar.setMinOutBpsAuraToUsdcMin(9600);
    }

    function test_setMinOutBpsAuraToUsdcMin_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.setMinOutBpsAuraToUsdcMin(5000);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Config: Manager/Owner
    ////////////////////////////////////////////////////////////////////////////

    function test_setMinOutBpsBalToUsdcVal() external {
        uint256 val;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MinOutBpsBalToUsdcValUpdated(9100, 9750);
        avatar.setMinOutBpsBalToUsdcVal(9100);
        (val,) = avatar.minOutBpsBalToUsdc();
        assertEq(val, 9100);

        vm.prank(manager);
        avatar.setMinOutBpsBalToUsdcVal(9200);
        (val,) = avatar.minOutBpsBalToUsdc();
        assertEq(val, 9200);
    }

    function test_setMinOutBpsBalToUsdcVal_invalidValues() external {
        vm.startPrank(owner);
        avatar.setMinOutBpsBalToUsdcMin(9000);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.InvalidBps.selector, 1000000));
        avatar.setMinOutBpsBalToUsdcVal(1000000);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.LessThanBpsMin.selector, 1000, 9000));
        avatar.setMinOutBpsBalToUsdcVal(1000);
    }

    function test_setMinOutBpsBalToUsdcVal_permissions() external {
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.NotOwnerOrManager.selector, (address(this))));
        avatar.setMinOutBpsBalToUsdcVal(9100);
    }

    function test_setMinOutBpsAuraToUsdcVal() external {
        uint256 val;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MinOutBpsAuraToUsdcValUpdated(9100, 9750);
        avatar.setMinOutBpsAuraToUsdcVal(9100);
        (val,) = avatar.minOutBpsAuraToUsdc();
        assertEq(val, 9100);

        vm.prank(manager);
        avatar.setMinOutBpsAuraToUsdcVal(9200);
        (val,) = avatar.minOutBpsAuraToUsdc();
        assertEq(val, 9200);
    }

    function test_setMinOutBpsAuraToUsdcVal_invalidValues() external {
        vm.startPrank(owner);
        avatar.setMinOutBpsAuraToUsdcMin(9000);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.InvalidBps.selector, 1000000));
        avatar.setMinOutBpsAuraToUsdcVal(1000000);

        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.LessThanBpsMin.selector, 1000, 9000));
        avatar.setMinOutBpsAuraToUsdcVal(1000);
    }

    function test_setMinOutBpsAuraToUsdcVal_permissions() external {
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.NotOwnerOrManager.selector, address(this)));
        avatar.setMinOutBpsAuraToUsdcVal(9100);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Actions: Owner
    ////////////////////////////////////////////////////////////////////////////

    function test_deposit() public {
        // Deposit both assets
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(BPT_80BADGER_20WBTC), 20 ether, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(BPT_40WBTC_40DIGG_20GRAVIAURA), 10 ether, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(BPT_50BADGER_50RETH), 10 ether, block.timestamp);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 10 ether;
        amountsDeposit[2] = 10 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        assertEq(BPT_80BADGER_20WBTC.balanceOf(owner), 0);
        assertEq(BPT_40WBTC_40DIGG_20GRAVIAURA.balanceOf(owner), 10e18);
        assertEq(BPT_50BADGER_50RETH.balanceOf(owner), 10e18);

        assertEq(BASE_REWARD_POOL_80BADGER_20WBTC.balanceOf(address(avatar)), 20e18);
        assertEq(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.balanceOf(address(avatar)), 10e18);
        assertEq(BASE_REWARD_POOL_50BADGER_50RETH.balanceOf(address(avatar)), 10e18);

        assertEq(avatar.lastClaimTimestamp(), 0);

        // Advancing in time
        skip(1 hours);

        // Single asset deposit
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(BPT_40WBTC_40DIGG_20GRAVIAURA), 10e18, block.timestamp);
        amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 10 ether;
        pidsInit = new uint256[](1);
        pidsInit[0] = pidsExpected[1];
        avatar.deposit(pidsInit, amountsDeposit);

        assertEq(BPT_40WBTC_40DIGG_20GRAVIAURA.balanceOf(owner), 0);

        assertEq(BASE_REWARD_POOL_80BADGER_20WBTC.balanceOf(address(avatar)), 20e18);
        assertEq(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.balanceOf(address(avatar)), 20e18);

        // lastClaimTimestamp is zero at cost of quick 1st harvest
        assertEq(avatar.lastClaimTimestamp(), 0);
    }

    function test_deposit_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);
    }

    function test_deposit_empty() public {
        vm.expectRevert(AuraAvatarMultiToken.NothingToDeposit.selector);
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);
    }

    function test_deposit_pid_not_in_storage() public {
        uint256[] memory amountsDeposit = new uint256[](1);
        amountsDeposit[0] = 20 ether;
        uint256[] memory pidsInit = new uint256[](1);
        pidsInit[0] = 120;
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.PidNotIncluded.selector, 120));
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);
    }

    function test_totalAssets() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        uint256[] memory assetAmounts = avatar.totalAssets();
        assertEq(assetAmounts[0], 20 ether);
        assertEq(assetAmounts[0], 20 ether);
    }

    function test_withdrawAll() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(BPT_80BADGER_20WBTC), 20e18, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(BPT_40WBTC_40DIGG_20GRAVIAURA), 20e18, block.timestamp);
        avatar.withdrawAll();

        assertEq(BASE_REWARD_POOL_80BADGER_20WBTC.balanceOf(address(avatar)), 0);
        assertEq(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.balanceOf(address(avatar)), 0);

        assertEq(BPT_80BADGER_20WBTC.balanceOf(owner), 20e18);
        assertEq(BPT_40WBTC_40DIGG_20GRAVIAURA.balanceOf(owner), 20e18);
    }

    function test_withdrawAll_nothing() public {
        vm.expectRevert(AuraAvatarMultiToken.NothingToWithdraw.selector);
        vm.prank(owner);
        avatar.withdrawAll();
    }

    function test_withdrawAll_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.withdrawAll();
    }

    function test_withdraw() public {
        vm.startPrank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(BPT_80BADGER_20WBTC), 10e18, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(BPT_40WBTC_40DIGG_20GRAVIAURA), 20e18, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(BPT_50BADGER_50RETH), 20e18, block.timestamp);
        uint256[] memory amountsWithdraw = new uint256[](3);
        amountsWithdraw[0] = 10 ether;
        amountsWithdraw[1] = 20 ether;
        amountsWithdraw[2] = 20 ether;
        avatar.withdraw(pidsInit, amountsWithdraw);

        assertEq(BPT_80BADGER_20WBTC.balanceOf(owner), 10e18);
        assertEq(BPT_40WBTC_40DIGG_20GRAVIAURA.balanceOf(owner), 20e18);
        assertEq(BPT_50BADGER_50RETH.balanceOf(owner), 20e18);
    }

    function test_withdraw_nothing() public {
        vm.expectRevert(AuraAvatarMultiToken.NothingToWithdraw.selector);
        vm.prank(owner);
        uint256[] memory amountsWithdraw = new uint256[](2);
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.withdraw(pidsInit, amountsWithdraw);
    }

    function test_withdraw_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        uint256[] memory amountsWithdraw = new uint256[](2);
        amountsWithdraw[0] = 20 ether;
        amountsWithdraw[1] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.withdraw(pidsInit, amountsWithdraw);
    }

    function test_claimRewardsAndSendToOwner() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        uint256 initialOwnerBal = BAL.balanceOf(owner);
        uint256 initialOwnerAura = AURA.balanceOf(owner);

        skip(1 hours);

        uint256 balReward1 = BASE_REWARD_POOL_80BADGER_20WBTC.earned(address(avatar));
        uint256 balReward2 = BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.earned(address(avatar));

        uint256 auraReward = getMintableAuraForBalAmount(balReward1 + balReward2);

        assertGt(balReward1, 0);
        assertGt(balReward2, 0);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(address(BAL), balReward1 + balReward2, block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(address(AURA), auraReward, block.timestamp);
        avatar.claimRewardsAndSendToOwner();

        assertEq(BASE_REWARD_POOL_80BADGER_20WBTC.earned(address(avatar)), 0);
        assertEq(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.earned(address(avatar)), 0);

        assertEq(BAL.balanceOf(address(avatar)), 0);
        assertEq(AURA.balanceOf(address(avatar)), 0);

        assertEq(BAL.balanceOf(owner) - initialOwnerBal, balReward1 + balReward2);
        assertEq(AURA.balanceOf(owner) - initialOwnerAura, auraReward);
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
        vm.expectRevert(AuraAvatarMultiToken.NoRewards.selector);
        vm.prank(owner);
        avatar.claimRewardsAndSendToOwner();
    }

    function test_addbpt_position_info_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.addBptPositionInfo(21);
    }

    function test_addbpt_position_infopt() public {
        vm.prank(owner);
        avatar.addBptPositionInfo(21);

        uint256[] memory avatarPids = avatar.getPids();
        bool pidIsAdded;

        for (uint256 i = 0; i < avatarPids.length; i++) {
            if (avatarPids[i] == 21) {
                pidIsAdded = true;
            }
        }

        assertTrue(pidIsAdded);
    }

    function test_removebpt_position_info_permissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        avatar.removeBptPositionInfo(21);
    }

    function test_removebpt_position_info_non_existent() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.PidNotIncluded.selector, 120));
        avatar.removeBptPositionInfo(120);
    }

    function test_removebpt_position_info_still_staked() public {
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                AuraAvatarMultiToken.BptStillStaked.selector,
                address(BPT_80BADGER_20WBTC),
                address(BASE_REWARD_POOL_80BADGER_20WBTC),
                20 ether
            )
        );
        vm.prank(owner);
        avatar.removeBptPositionInfo(PID_80BADGER_20WBTC);
    }

    function test_removebpt_position_info() public {
        vm.prank(owner);
        avatar.removeBptPositionInfo(PID_80BADGER_20WBTC);

        uint256[] memory avatarPids = avatar.getPids();

        bool pidIsPresent;

        for (uint256 i = 0; i < avatarPids.length; i++) {
            if (avatarPids[i] == 21) {
                pidIsPresent = true;
            }
        }

        assertFalse(pidIsPresent);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Actions: Owner/Manager
    ////////////////////////////////////////////////////////////////////////////

    function checked_processRewards(uint256 _auraPriceInUsd) internal {
        (,, uint256 voterBalanceBefore,) = AURA_LOCKER.lockedBalances(BADGER_VOTER);
        uint256 usdcBalanceBefore = USDC.balanceOf(owner);

        assertGt(BASE_REWARD_POOL_80BADGER_20WBTC.earned(address(avatar)), 0);
        assertGt(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.earned(address(avatar)), 0);

        address[2] memory actors = [owner, manager];
        for (uint256 i; i < actors.length; ++i) {
            uint256 snapId = vm.snapshot();

            vm.prank(actors[i]);
            vm.expectEmit(false, false, false, false);
            emit RewardsToStable(address(USDC), 0, block.timestamp);
            TokenAmount[] memory processed = avatar.processRewards(_auraPriceInUsd);

            (,, uint256 voterBalanceAfter,) = AURA_LOCKER.lockedBalances(BADGER_VOTER);

            assertEq(processed[0].token, address(USDC));
            assertEq(processed[1].token, address(AURA));

            assertGt(processed[0].amount, 0);
            assertGt(processed[1].amount, 0);

            assertEq(BASE_REWARD_POOL_80BADGER_20WBTC.earned(address(avatar)), 0);
            assertEq(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.earned(address(avatar)), 0);

            assertEq(BAL.balanceOf(address(avatar)), 0);
            assertEq(AURA.balanceOf(address(avatar)), 0);

            assertGt(voterBalanceAfter, voterBalanceBefore);
            assertGt(USDC.balanceOf(owner), usdcBalanceBefore);

            vm.revertTo(snapId);
        }
    }

    function test_processRewards() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skipAndForwardFeeds(1 hours);

        (, uint256 pendingAura) = avatar.pendingRewards();
        checked_processRewards(getAuraPriceInUsdSpot(pendingAura));
    }

    function test_processRewards_noAuraPrice() public {
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        vm.prank(owner);
        avatar.deposit(pidsInit, amountsDeposit);

        skipAndForwardFeeds(1 hours);

        checked_processRewards(0);
    }

    function test_processRewards_permissions() public {
        vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.NotOwnerOrManager.selector, address(this)));
        avatar.processRewards(0);
    }

    function test_processRewards_noRewards() public {
        vm.expectRevert(AuraAvatarMultiToken.NoRewards.selector);
        vm.prank(owner);
        avatar.processRewards(0);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Actions: Keeper
    ////////////////////////////////////////////////////////////////////////////

    function test_checkUpkeep() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skip(1 weeks);

        (bool upkeepNeeded, bytes memory performData) = avatar.checkUpkeep(new bytes(0));
        assertTrue(upkeepNeeded);
    }

    function test_checkUpkeep_premature() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);
        skipAndForwardFeeds(1 weeks);

        bool upkeepNeeded;

        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertTrue(upkeepNeeded);

        vm.prank(keeper);
        avatar.performUpkeep(abi.encodeCall(AuraAvatarMultiToken.processRewardsKeeper, uint256(0)));

        skip(1 weeks - 1);

        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertFalse(upkeepNeeded);
    }

    function test_performUpkeep() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        (,, uint256 voterBalanceBefore,) = AURA_LOCKER.lockedBalances(BADGER_VOTER);
        uint256 usdcBalanceBefore = USDC.balanceOf(owner);

        skipAndForwardFeeds(1 weeks);

        bool upkeepNeeded;
        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertTrue(upkeepNeeded);

        vm.prank(keeper);
        vm.expectEmit(false, false, false, false);
        emit RewardsToStable(address(USDC), 0, block.timestamp);
        avatar.performUpkeep(abi.encodeCall(AuraAvatarMultiToken.processRewardsKeeper, uint256(0)));

        // Ensure that rewards were processed properly
        assertEq(BASE_REWARD_POOL_80BADGER_20WBTC.earned(address(avatar)), 0);
        assertEq(BASE_REWARD_POOL_40WBTC_40DIGG_20GRAVIAURA.earned(address(avatar)), 0);

        assertEq(BAL.balanceOf(address(avatar)), 0);
        assertEq(AURA.balanceOf(address(avatar)), 0);

        (,, uint256 voterBalanceAfter,) = AURA_LOCKER.lockedBalances(BADGER_VOTER);
        assertGt(voterBalanceAfter, voterBalanceBefore);
        assertGt(USDC.balanceOf(owner), usdcBalanceBefore);

        // Upkeep is not needed anymore
        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertFalse(upkeepNeeded);
    }

    function test_performUpkeep_permissions() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        address[3] memory actors = [address(this), owner, manager];
        for (uint256 i; i < actors.length; ++i) {
            uint256 snapId = vm.snapshot();

            vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.NotKeeper.selector, actors[i]));
            vm.prank(actors[i]);
            avatar.performUpkeep(new bytes(0));

            vm.revertTo(snapId);
        }
    }

    function test_performUpkeep_premature() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skipAndForwardFeeds(1 weeks);

        (bool upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertTrue(upkeepNeeded);

        vm.prank(keeper);
        avatar.performUpkeep(abi.encodeCall(AuraAvatarMultiToken.processRewardsKeeper, uint256(0)));

        skip(1 weeks - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuraAvatarMultiToken.TooSoon.selector,
                block.timestamp,
                avatar.lastClaimTimestamp(),
                avatar.claimFrequency()
            )
        );
        vm.prank(keeper);
        avatar.performUpkeep(abi.encodeCall(AuraAvatarMultiToken.processRewardsKeeper, uint256(0)));
    }

    function test_performUpkeep_staleFeed() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skip(1 weeks);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuraAvatarUtils.StalePriceFeed.selector, block.timestamp, BAL_USD_FEED.latestTimestamp(), 24 hours
            )
        );
        vm.prank(keeper);
        avatar.performUpkeep(abi.encodeCall(AuraAvatarMultiToken.processRewardsKeeper, uint256(0)));
    }

    function test_processRewardsKeeper_permissions() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        address[3] memory actors = [address(this), owner, manager];
        for (uint256 i; i < actors.length; ++i) {
            uint256 snapId = vm.snapshot();

            vm.expectRevert(abi.encodeWithSelector(AuraAvatarMultiToken.NotKeeper.selector, actors[i]));
            vm.prank(actors[i]);
            avatar.processRewardsKeeper(0);

            vm.revertTo(snapId);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    // MISC
    ////////////////////////////////////////////////////////////////////////////

    function test_getAuraPriceInUsdSpot() public {
        vm.startPrank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skipAndForwardFeeds(1 hours);

        (, uint256 pendingAura) = avatar.pendingRewards();

        uint256 spotPrice = getAuraPriceInUsdSpot(pendingAura) / 1e2;
        uint256 twapPrice = getAuraAmountInUsdc(1e18, 1 hours);

        // Spot price is within 2.5% of TWAP
        assertApproxEqRel(spotPrice, twapPrice, 0.025e18);
    }

    function test_checkUpkeep_price() public {
        vm.startPrank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skip(1 weeks);
        (, uint256 pendingAura) = avatar.pendingRewards();
        console.log(getAuraPriceInUsdSpot(pendingAura));

        (, bytes memory performData) = avatar.checkUpkeep(new bytes(0));
        uint256 auraPriceInUsd = getPriceFromPerformData(performData);

        uint256 spotPrice = getAuraPriceInUsdSpot(pendingAura);

        assertEq(auraPriceInUsd, spotPrice);
    }

    function test_debug() public {
        console.log(getBalAmountInUsdc(1e18));
        console.log(getAuraAmountInUsdc(1e18, avatar.twapPeriod()));

        vm.startPrank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skip(1 weeks);
        (, uint256 pendingAura) = avatar.pendingRewards();
        console.log(getAuraPriceInUsdSpot(pendingAura));

        (, bytes memory performData) = avatar.checkUpkeep(new bytes(0));
        uint256 auraPriceInUsd = getPriceFromPerformData(performData);
        console.log(auraPriceInUsd);
    }

    function test_processRewards_highBalMinBps() public {
        vm.startPrank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skip(1 hours);

        avatar.setMinOutBpsBalToUsdcVal(MAX_BPS);

        vm.expectRevert("BAL#507");
        avatar.processRewards(0);
    }

    function test_upkeep() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skipAndForwardFeeds(1 weeks);

        (bool upkeepNeeded, bytes memory performData) = avatar.checkUpkeep(new bytes(0));

        assertTrue(upkeepNeeded);

        vm.prank(keeper);
        avatar.performUpkeep(performData);
    }

    function test_processRewardsKeeper() public {
        vm.prank(owner);
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];
        avatar.deposit(pidsInit, amountsDeposit);

        skipAndForwardFeeds(1 weeks);

        (bool upkeepNeeded, bytes memory performData) = avatar.checkUpkeep(new bytes(0));
        uint256 auraPriceInUsd = getPriceFromPerformData(performData);

        assertTrue(upkeepNeeded);
        assertGt(auraPriceInUsd, 0);

        assertTrue(upkeepNeeded);

        vm.prank(keeper);
        avatar.performUpkeep(performData);

        // Upkeep is not needed anymore
        (upkeepNeeded,) = avatar.checkUpkeep(new bytes(0));
        assertFalse(upkeepNeeded);
    }

    function test_upkeep_allUsdc() public {
        uint256[] memory amountsDeposit = new uint256[](3);
        amountsDeposit[0] = 20 ether;
        amountsDeposit[1] = 20 ether;
        amountsDeposit[2] = 20 ether;
        uint256[] memory pidsInit = new uint256[](3);
        pidsInit[0] = pidsExpected[0];
        pidsInit[1] = pidsExpected[1];
        pidsInit[2] = pidsExpected[2];

        vm.startPrank(owner);
        avatar.setSellBpsAuraToUsdc(MAX_BPS);

        avatar.deposit(pidsInit, amountsDeposit);
        vm.stopPrank();

        skipAndForwardFeeds(1 weeks);

        (, bytes memory performData) = avatar.checkUpkeep(new bytes(0));

        uint256 usdcBalBefore = USDC.balanceOf(owner);
        (,, uint256 voterBalanceBefore,) = AURA_LOCKER.lockedBalances(BADGER_VOTER);

        vm.prank(keeper);
        avatar.performUpkeep(performData);

        (,, uint256 voterBalanceAfter,) = AURA_LOCKER.lockedBalances(BADGER_VOTER);

        // Check expected behaviour when all goes to usdc
        assertGt(USDC.balanceOf(owner), usdcBalBefore);
        assertEq(voterBalanceAfter, voterBalanceBefore);
    }

    ////////////////////////////////////////////////////////////////////////////
    // Internal helpers
    ////////////////////////////////////////////////////////////////////////////

    function skipAndForwardFeeds(uint256 _duration) internal {
        skip(_duration);
        forwardClFeed(BAL_USD_FEED, _duration);
        forwardClFeed(BAL_ETH_FEED, _duration);
        forwardClFeed(ETH_USD_FEED, _duration);
    }

    function forwardClFeed(IAggregatorV3 _feed) internal {
        int256 lastAnswer = _feed.latestAnswer();
        vm.etch(address(_feed), type(MockV3Aggregator).runtimeCode);
        MockV3Aggregator(address(_feed)).updateAnswer(lastAnswer);
    }

    function forwardClFeed(IAggregatorV3 _feed, uint256 _duration) internal {
        int256 lastAnswer = _feed.latestAnswer();
        uint256 lastTimestamp = _feed.latestTimestamp();
        vm.etch(address(_feed), type(MockV3Aggregator).runtimeCode);
        MockV3Aggregator(address(_feed)).updateAnswerAndTimestamp(lastAnswer, lastTimestamp + _duration);
    }

    function getPriceFromPerformData(bytes memory _performData) internal pure returns (uint256 auraPriceInUsd_) {
        assembly {
            auraPriceInUsd_ := mload(add(_performData, 36))
        }
    }
}