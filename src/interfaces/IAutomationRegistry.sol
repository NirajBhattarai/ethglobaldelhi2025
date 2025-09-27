// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IAutomationRegistry
 * @notice Interface for Chainlink Automation Registry
 */
interface IAutomationRegistry {
    /**
     * @notice adds a new upkeep
     * @param target address to perform upkeep on
     * @param gasLimit amount of gas to provide the target contract when
     * performing upkeep
     * @param admin address to cancel upkeep and withdraw remaining funds
     * @param checkData data passed to the contract when checking for upkeep
     */
    function registerUpkeep(address target, uint32 gasLimit, address admin, bytes calldata checkData)
        external
        returns (uint256 id);

    /**
     * @notice adds LINK funds for an upkeep
     * @param id upkeep to fund
     * @param amount amount of LINK to fund
     */
    function addFunds(uint256 id, uint96 amount) external;

    /**
     * @notice updates the check data for an upkeep
     * @param id upkeep to update
     * @param newCheckData new check data
     */
    function updateCheckData(uint256 id, bytes calldata newCheckData) external;

    /**
     * @notice cancels an upkeep
     * @param id upkeep to cancel
     */
    function cancelUpkeep(uint256 id) external;

    /**
     * @notice pauses an upkeep
     * @param id upkeep to pause
     */
    function pauseUpkeep(uint256 id) external;

    /**
     * @notice unpauses an upkeep
     * @param id upkeep to unpause
     */
    function unpauseUpkeep(uint256 id) external;

    /**
     * @notice gets upkeep information
     * @param id upkeep to get info for
     */
    function getUpkeep(uint256 id)
        external
        view
        returns (
            address target,
            uint32 executeGas,
            bytes memory checkData,
            uint96 balance,
            address lastKeeper,
            address admin,
            uint64 maxValidBlocknumber,
            uint96 amountSpent,
            bool paused
        );
}
