// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IKdexitRestrictedSellAdapter} from "../interfaces/IKdexitRestrictedSellAdapter.sol";
import {IPancakeSwapV2RouterLike} from "../interfaces/IPancakeSwapV2RouterLike.sol";
import {KdexitRoles} from "../access/KdexitRoles.sol";
import {KdexitTypes} from "../libraries/KdexitTypes.sol";

/// @title KdexitPancakeSwapRestrictedSellAdapter
/// @notice Disabled-by-default PancakeSwap-compatible restricted sell adapter scaffold.
/// @dev This adapter is for BSC testnet/internal-beta work only. It has no generic
/// calldata path, no treasury logic, no fee extraction, no upgradeability, and no
/// admin token sweep. It must be called only by the restricted execution controller.
contract KdexitPancakeSwapRestrictedSellAdapter is
    IKdexitRestrictedSellAdapter,
    AccessControl
{
    error AdminAddressZero();
    error RestrictedControllerAddressZero();
    error RouterAddressZero();
    error UnsupportedChain(uint256 expectedChainId, uint256 actualChainId);
    error AdapterDisabled();
    error UnauthorizedAdapterCaller(address caller);
    error InvalidAdapterParam(address expectedAdapter, address actualAdapter);
    error UserAddressZero();
    error TokenInAddressZero();
    error TokenOutAddressZero();
    error AmountInZero();
    error MinAmountOutZero();
    error RestrictedSellExpired(uint64 deadline, uint256 currentTime);
    error RouterReturnedInvalidAmounts();

    bytes32 public constant override adapterId = keccak256("KDEXIT_PANCAKESWAP_V2_RESTRICTED_SELL_TESTNET");

    address public immutable RESTRICTED_EXECUTION_CONTROLLER;
    IPancakeSwapV2RouterLike public immutable ROUTER;
    uint256 public immutable SUPPORTED_CHAIN_ID;

    bool public testnetExecutionEnabled;

    event PancakeSwapRestrictedSellAdapterEnabled(address indexed actor, bool enabled);

    event PancakeSwapRestrictedSellExecuted(
        address indexed user,
        bytes32 indexed strategyId,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minAmountOut,
        address router,
        uint64 deadline
    );

    constructor(
        address defaultAdmin,
        address restrictedExecutionController,
        address router,
        uint256 supportedChainId
    ) {
        if (defaultAdmin == address(0)) revert AdminAddressZero();
        if (restrictedExecutionController == address(0)) {
            revert RestrictedControllerAddressZero();
        }
        if (router == address(0)) revert RouterAddressZero();

        RESTRICTED_EXECUTION_CONTROLLER = restrictedExecutionController;
        ROUTER = IPancakeSwapV2RouterLike(router);
        SUPPORTED_CHAIN_ID = supportedChainId;

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(KdexitRoles.ADMIN_ROLE, defaultAdmin);
    }

    /// @notice Enables or disables the testnet adapter path.
    /// @dev Disabled is the deployment default. Enabling this does not bypass the
    /// controller allowlist, token allowlist, relayer gate, pause gate, or EIP-712
    /// authorization flow expected before any caller reaches this adapter.
    function setTestnetExecutionEnabled(bool enabled) external onlyRole(KdexitRoles.ADMIN_ROLE) {
        testnetExecutionEnabled = enabled;
        emit PancakeSwapRestrictedSellAdapterEnabled(msg.sender, enabled);
    }

    /// @notice Executes a simple PancakeSwap-compatible exact-input token sell path.
    /// @dev This scaffold does not approve tokens. A future testnet execution module
    /// must define how exact, bounded token allowance reaches the router safely.
    /// Persistent unlimited approvals are not safe for production. This function
    /// also does not custody user funds by itself; any token staging model must be
    /// separately reviewed before real beta use.
    function executeRestrictedSell(KdexitTypes.RestrictedSellParams calldata params)
        external
        override
        returns (uint256 amountOut)
    {
        if (msg.sender != RESTRICTED_EXECUTION_CONTROLLER) {
            revert UnauthorizedAdapterCaller(msg.sender);
        }
        if (block.chainid != SUPPORTED_CHAIN_ID) {
            revert UnsupportedChain(SUPPORTED_CHAIN_ID, block.chainid);
        }
        if (!testnetExecutionEnabled) revert AdapterDisabled();

        _validateParams(params);

        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
            params.amountIn, params.minAmountOut, path, params.user, params.deadline
        );
        if (amounts.length < 2) revert RouterReturnedInvalidAmounts();

        amountOut = amounts[amounts.length - 1];
        emit PancakeSwapRestrictedSellExecuted(
            params.user,
            params.strategyId,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            params.minAmountOut,
            address(ROUTER),
            params.deadline
        );
    }

    function _validateParams(KdexitTypes.RestrictedSellParams calldata params) internal view {
        if (params.adapter != address(this)) {
            revert InvalidAdapterParam(address(this), params.adapter);
        }
        if (params.user == address(0)) revert UserAddressZero();
        if (params.tokenIn == address(0)) revert TokenInAddressZero();
        if (params.tokenOut == address(0)) revert TokenOutAddressZero();
        if (params.amountIn == 0) revert AmountInZero();
        if (params.minAmountOut == 0) revert MinAmountOutZero();
        if (params.deadline < block.timestamp) {
            revert RestrictedSellExpired(params.deadline, block.timestamp);
        }
    }
}
