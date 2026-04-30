// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData)
        external;
    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter
    ) external;
    function warp(uint256 newTimestamp) external;
    function sign(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (uint8 v, bytes32 r, bytes32 s);
    function addr(uint256 privateKey) external pure returns (address keyAddr);
}

abstract contract BaseTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error AssertionFailed(string message);

    function assertTrue(bool condition, string memory message) internal pure {
        if (!condition) revert AssertionFailed(message);
    }

    function assertFalse(bool condition, string memory message) internal pure {
        if (condition) revert AssertionFailed(message);
    }

    function assertEq(address left, address right, string memory message) internal pure {
        if (left != right) revert AssertionFailed(message);
    }

    function assertEq(bytes32 left, bytes32 right, string memory message) internal pure {
        if (left != right) revert AssertionFailed(message);
    }

    function assertEq(uint256 left, uint256 right, string memory message) internal pure {
        if (left != right) revert AssertionFailed(message);
    }

    function assertEq(bool left, bool right, string memory message) internal pure {
        if (left != right) revert AssertionFailed(message);
    }
}
