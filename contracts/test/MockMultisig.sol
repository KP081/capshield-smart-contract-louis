// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "solady/src/auth/OwnableRoles.sol";

/**
 * @title MockMultisig
 * @notice Simple mock contract to simulate a multisig wallet for testing
 * @dev This contract inherits OwnableRoles to act as admin and can delegate role management
 */
contract MockMultisig is OwnableRoles {
    /**
     * @notice Initialize the mock multisig with an owner
     * @param _owner The EOA that controls this multisig for testing
     */
    constructor(address _owner) {
        _initializeOwner(_owner);
    }

    /**
     * @notice Execute an arbitrary call from this multisig
     * @param target Target contract address
     * @param data Calldata to send
     */
    function execute(address target, bytes calldata data) external payable onlyOwner returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        if (!success) {
            // Bubble up the revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        return result;
    }

    /**
     * @notice Allow receiving ETH
     */
    receive() external payable {}
}
