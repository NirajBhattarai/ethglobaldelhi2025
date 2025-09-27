// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAutomationRegistrar
 * @notice Interface for Chainlink Automation Registrar
 */
interface IAutomationRegistrar {
    struct RegistrationParams {
        string name;
        bytes encryptedEmail;
        address upkeepContract;
        uint32 gasLimit;
        address adminAddress;
        uint8 triggerType;
        bytes checkData;
        bytes triggerConfig;
        bytes offchainConfig;
        uint96 amount;
    }

    /**
     * @notice Registers a new upkeep
     * @param requestParams The registration parameters
     * @return upkeepId The ID of the registered upkeep
     */
    function registerUpkeep(RegistrationParams memory requestParams) external returns (uint256 upkeepId);

    /**
     * @notice Cancels a pending registration request
     * @param hash The hash of the registration request
     */
    function cancel(bytes32 hash) external;

    /**
     * @notice Gets the minimum LINK amount required for registration
     * @return minLINKJuels The minimum LINK amount in juels
     */
    function getMinLINKJuels() external view returns (uint96 minLINKJuels);
}
