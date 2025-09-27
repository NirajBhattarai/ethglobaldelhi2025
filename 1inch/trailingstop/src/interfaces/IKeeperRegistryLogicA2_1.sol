// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IKeeperRegistryLogicA2_1
 * @notice Interface for KeeperRegistryLogicA2_1 contract
 * @dev Minimal interface to avoid version conflicts
 */
interface IKeeperRegistryLogicA2_1 {
    /**
     * @notice updates the checkData for an upkeep
     * @param id the upkeep ID
     * @param newCheckData the new check data
     */
    function setUpkeepCheckData(uint256 id, bytes calldata newCheckData) external;
}
