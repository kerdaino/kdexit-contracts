// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {KdexitPancakeSwapRestrictedSellAdapter} from "../../src/adapters/KdexitPancakeSwapRestrictedSellAdapter.sol";
import {KdexitTypes} from "../../src/libraries/KdexitTypes.sol";
import {FakePancakeSwapV2Router} from "../mocks/FakePancakeSwapV2Router.sol";
import {MockRestrictedSellAdapter} from "../mocks/MockRestrictedSellAdapter.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract KdexitPancakeSwapRestrictedSellAdapterTest is BaseTest {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant RESTRICTED_CONTROLLER = address(0xC041);
    address internal constant USER = address(0xACC0);
    address internal constant TOKEN_IN = address(0x7001);
    address internal constant TOKEN_OUT = address(0x7002);
    address internal constant OTHER_ADAPTER = address(0xADBB);

    bytes32 internal constant STRATEGY_ID = keccak256("kdexit.strategy.alpha");
    bytes32 internal constant MOCK_ADAPTER_ID = keccak256("kdexit.adapter.local-mock");

    FakePancakeSwapV2Router internal router;
    KdexitPancakeSwapRestrictedSellAdapter internal adapter;

    function setUp() public {
        router = new FakePancakeSwapV2Router(950 ether);
        adapter = new KdexitPancakeSwapRestrictedSellAdapter(
            ADMIN, RESTRICTED_CONTROLLER, address(router), block.chainid
        );
    }

    function testAdapterRejectsInvalidParams() public {
        vm.prank(ADMIN);
        adapter.setTestnetExecutionEnabled(true);

        KdexitTypes.RestrictedSellParams memory params = _makeParams();
        params.adapter = OTHER_ADAPTER;

        vm.prank(RESTRICTED_CONTROLLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitPancakeSwapRestrictedSellAdapter.InvalidAdapterParam.selector,
                address(adapter),
                OTHER_ADAPTER
            )
        );
        adapter.executeRestrictedSell(params);
    }

    function testAdapterCannotBeUsedForArbitraryCalls() public {
        KdexitTypes.RestrictedSellParams memory params = _makeParams();

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                KdexitPancakeSwapRestrictedSellAdapter.UnauthorizedAdapterCaller.selector,
                USER
            )
        );
        adapter.executeRestrictedSell(params);
    }

    function testAdapterRespectsMinAmountOutAssumption() public {
        vm.prank(ADMIN);
        adapter.setTestnetExecutionEnabled(true);
        router.setAmountOut(800 ether);

        KdexitTypes.RestrictedSellParams memory params = _makeParams();

        vm.prank(RESTRICTED_CONTROLLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                FakePancakeSwapV2Router.FakeRouterInsufficientOutput.selector,
                800 ether,
                params.minAmountOut
            )
        );
        adapter.executeRestrictedSell(params);
    }

    function testAdapterIsDisabledByDefault() public {
        KdexitTypes.RestrictedSellParams memory params = _makeParams();

        vm.prank(RESTRICTED_CONTROLLER);
        vm.expectRevert(
            abi.encodeWithSelector(KdexitPancakeSwapRestrictedSellAdapter.AdapterDisabled.selector)
        );
        adapter.executeRestrictedSell(params);
    }

    function testPancakeAdapterRemainsSeparateFromMockAdapter() public {
        MockRestrictedSellAdapter mockAdapter =
            new MockRestrictedSellAdapter(MOCK_ADAPTER_ID, 950 ether);

        assertFalse(address(adapter) == address(mockAdapter), "adapter address should differ");
        assertFalse(adapter.adapterId() == mockAdapter.adapterId(), "adapter ids should differ");
    }

    function _makeParams() internal view returns (KdexitTypes.RestrictedSellParams memory) {
        return KdexitTypes.RestrictedSellParams({
            user: USER,
            strategyId: STRATEGY_ID,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            amountIn: 1 ether,
            minAmountOut: 900 ether,
            adapter: address(adapter),
            deadline: uint64(block.timestamp + 1 days)
        });
    }
}
