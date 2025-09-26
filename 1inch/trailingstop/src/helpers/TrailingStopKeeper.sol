// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {IAutomationCompatible} from "../interfaces/IAutomationCompatible.sol";
import {TrailingStopOrder} from "../extensions/TrailingStopOrder.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract TrailingStopKeeper is IAutomationCompatible {
    // libraries

    // errors

    error NoOrdersToProcess();

    // storages

    TrailingStopOrder public trailingStopOrder;

    constructor(address _trailingStopOrder) {
        trailingStopOrder = TrailingStopOrder(_trailingStopOrder);
    }

    function performUpkeep(bytes calldata checkData) external override {
        // decode all Trailing Stop Order hashes
        bytes32[] memory orderHashes = abi.decode(checkData, (bytes32[]));

        if (orderHashes.length == 0) {
            revert NoOrdersToProcess();
        }

        // TODO: discuss with 1inch to handle threshold amount of orders to process

        uint256 ordersProcessed = 0;
        uint256 ordersUpdated = 0;

        for (uint256 i = 0; i < orderHashes.length; i++) {
            //TODO: process order
            ordersProcessed++;
            ordersUpdated++;
        }
    }

    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // Decode order hashes from performData
        bytes32[] memory orderHashes = abi.decode(performData, (bytes32[]));

        for (uint256 i = 0; i < orderHashes.length; i++) {
            (
                AggregatorV3Interface makerAssetOracle,
                uint256 initialStopPrice,
                uint256 trailingDistance,
                uint256 currentStopPrice,
                uint256 configuredAt,
                uint256 lastUpdateAt,
                uint256 updateFrequency
            ) = trailingStopOrder.trailingStopConfigs(orderHashes[i]);
        }

        if (orderHashes.length == 0) {
            return (false, "");
        }

        for (uint256 i = 0; i < orderHashes.length; i++) {
            (
                AggregatorV3Interface makerAssetOracle,
                uint256 initialStopPrice,
                uint256 trailingDistance,
                uint256 currentStopPrice,
                uint256 configuredAt,
                uint256 lastUpdateAt,
                uint256 updateFrequency
            ) = trailingStopOrder.trailingStopConfigs(orderHashes[i]);

            // must be created and update frequency has passed
            if (configuredAt > 0 && block.timestamp >= configuredAt + updateFrequency) {
                return (true, checkData); // Return checkData as performData
            }
        }
        return (false, "");
    }
}
