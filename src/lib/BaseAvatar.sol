// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Enum, Executor} from "safe-contracts/base/Executor.sol";

import {GlobalAccessControlManaged} from "./GlobalAccessControlManaged.sol";

/**
 * Avatar
 * Forwards calls from the owner
 */
contract BaseAvatar is OwnableUpgradeable, Executor {
    function __BaseAvatar_init(address _owner) public onlyInitializing {
        __Ownable_init_unchained();

        transferOwnership(_owner);
    }

    /// ===== View Functions =====

    /// @notice Used to track the deployed version of BaseAvatar.
    /// @return Current version of the contract.
    function baseAvatarVersion() external pure returns (string memory) {
        return "1.0";
    }

    /// ===== Permissioned Actions: Owner =====

    /**
     * @dev Make arbitrary Ethereum call
     * @param to Address to call
     * @param value ETH value
     * @param data TX data
     */
    function call(address to, uint256 value, bytes memory data)
        public
        payable
        virtual
        onlyOwner
        returns (bool success)
    {
        // TODO: Check why delegatecall
        return execute(to, value, data, Enum.Operation.DelegateCall, gasleft());
    }
}
