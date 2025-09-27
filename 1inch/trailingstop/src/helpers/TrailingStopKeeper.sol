// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {IAutomationCompatible} from "../interfaces/IAutomationCompatible.sol";
import {TrailingStopOrder} from "../extensions/TrailingStopOrder.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract TrailingStopKeeper is IAutomationCompatible {
    // libraries

    // errors

    error NoOrdersToProcess();
    error UnauthorizedCaller();

    // events

    event BatchUpdateCompleted(uint256 ordersProcessed, uint256 ordersUpdated, uint256 gasUsed);

    // storages

    TrailingStopOrder public trailingStopOrder;

    mapping(bytes32 => bool) public processedOrders; // Track processed orders in current batch and skip to save gas

    // stats
    uint256 public lastProcessedBlock;
    uint256 public totalOrdersProcessed;
    uint256 public totalUpdatesPerformed;

    constructor(address _trailingStopOrder) {
        trailingStopOrder = TrailingStopOrder(_trailingStopOrder);
    }

    // TODO: this was meant to be internal function but can't use try catch while calling this function will see later
    //  try making internal while writing the tests
    function _processOrder(bytes32 orderHash) external returns (bool updated) {
        if (msg.sender != address(this)) {
            revert UnauthorizedCaller();
        }
        // Update trailing stop price
        try trailingStopOrder.updateTrailingStop(orderHash) {
            updated = true;
        } catch {
            updated = false;
        }

        return updated;
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
            bytes32 orderHash = orderHashes[i]; // get order hash

            // Skip if already processed in this batch
            if (processedOrders[orderHash]) {
                continue;
            }

            try this._processOrder(orderHash) {
                processedOrders[orderHash] = true;
                ordersUpdated++;
                ordersProcessed++;
            } catch {
                // Order processing failed, continue to next order
                ordersProcessed++;
            }
        }

        // Clear processed orders mapping for next batch
        for (uint256 i = 0; i < orderHashes.length; i++) {
            delete processedOrders[orderHashes[i]];
        }

        totalOrdersProcessed += ordersProcessed;
        totalUpdatesPerformed += ordersUpdated;
        lastProcessedBlock = block.number;

        emit BatchUpdateCompleted(ordersProcessed, ordersUpdated, block.gaslimit);
    }

    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // Decode order hashes from checkData
        bytes32[] memory orderHashes = abi.decode(checkData, (bytes32[]));

        if (orderHashes.length == 0) {
            return (false, "");
        }

        for (uint256 i = 0; i < orderHashes.length; i++) {
            (
                , // AggregatorV3Interface makerAssetOracle
                , // uint256 initialStopPrice
                , // uint256 trailingDistance
                , // uint256 currentStopPrice
                uint256 configuredAt,
                uint256 lastUpdateAt,
                uint256 updateFrequency,
                , // uint256 maxSlippage
                , // uint256 maxPriceDeviation
                , // uint256 twapWindow
                , // address keeper
                , // TrailingStopOrder.OrderType orderType
                , // uint8 makerAssetDecimals
                    // uint8 takerAssetDecimals
            ) = trailingStopOrder.trailingStopConfigs(orderHashes[i]);

            // must be created and update frequency has passed
            if (configuredAt > 0 && block.timestamp >= lastUpdateAt + updateFrequency) {
                return (true, checkData); // Return checkData as performData
            }
        }
        return (false, "");
    }

    /**
     * @notice Get keeper statistics
     * @return totalProcessed Total orders processed
     * @return totalUpdates Total updates performed
     * @return lastBlock Last processed block
     */
    function getKeeperStats() external view returns (uint256 totalProcessed, uint256 totalUpdates, uint256 lastBlock) {
        return (totalOrdersProcessed, totalUpdatesPerformed, lastProcessedBlock);
    }
}
