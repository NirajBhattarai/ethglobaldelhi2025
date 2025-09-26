// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {IAutomationCompatible} from "../interfaces/IAutomationCompatible.sol";

contract TrailingStopKeeper is IAutomationCompatible {
    function performUpkeep(bytes calldata checkData) external override {
        // TODO: Implement performUpkeep
    }

    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // TODO: Implement checkUpkeep
    }
}
