// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {AmountGetterBase} from "./AmountGetterBase.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract TrailingStopOrder is AmountGetterBase {
    // libraries

    // errors

    error InvalidMakerAssetOracle();
    error InvalidTrailingDistance();

    // structs

    struct TrailingStopConfig {
        AggregatorV3Interface makerAssetOracle;
        uint256 initialStopPrice; // initial stop price in maker asset
        uint256 trailingDistance; // trailing distance in maker asset
        uint256 currentStopPrice; // updated stop price in maker asset
    }

    // constants

    // storages

    mapping(bytes32 => TrailingStopConfig) public trailingStopConfigs;

    // events

    event TrailingStopConfigUpdated(
        address indexed maker, address indexed makerAssetOracle, uint256 initialStopPrice, uint256 trailingDistance
    );

    // modifiers

    function configureTrailingStop(bytes32 orderHash, TrailingStopConfig calldata config) external {
        address maker = msg.sender;

        if (address(config.makerAssetOracle) == address(0)) {
            revert InvalidMakerAssetOracle();
        }

        if (config.initialStopPrice == 0) {
            revert InvalidTrailingDistance();
        }

        TrailingStopConfig storage storedConfig = trailingStopConfigs[orderHash];
        storedConfig.makerAssetOracle = config.makerAssetOracle;
        storedConfig.initialStopPrice = config.initialStopPrice;
        storedConfig.trailingDistance = config.trailingDistance;
        storedConfig.currentStopPrice = config.initialStopPrice;

        emit TrailingStopConfigUpdated(
            maker, address(config.makerAssetOracle), config.initialStopPrice, config.trailingDistance
        );
    }
}
