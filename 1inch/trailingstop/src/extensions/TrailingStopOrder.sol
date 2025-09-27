// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

// Chainlink imports
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// OpenZeppelin imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// 1inch imports
import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";

// Local imports
import {AmountGetterBase} from "./AmountGetterBase.sol";
import {IOrderMixin} from "../interfaces/IOrderMixin.sol";
import {IPreInteraction} from "../interfaces/IPreInteraction.sol";
import {ITakerInteraction} from "../interfaces/ITakerInteraction.sol";

/**
 * @title TrailingStopOrder
 * @notice A contract that implements the trailing stop order functionality for the 1inch Limit Order Protocol.
 */
contract TrailingStopOrder is AmountGetterBase, Pausable, Ownable, IPreInteraction {
    // libraries
    using Math for uint256;
    using SafeERC20 for IERC20;

    // errors

    error InvalidMakerAssetOracle();
    error InvalidTrailingDistance();
    error TrailingStopNotConfigured();
    error InvalidUpdateFrequency();
    error TrailingStopNotTriggered();

    // structs

    struct TrailingStopConfig {
        AggregatorV3Interface makerAssetOracle;
        uint256 initialStopPrice; // initial stop price in maker asset
        uint256 trailingDistance; // trailing distance in maker asset
        uint256 currentStopPrice; // updated stop price in maker asset
        uint256 configuredAt; // timestamp when the trailing stop was configured
        uint256 lastUpdateAt; // timestamp when the trailing stop was last updated
        uint256 updateFrequency; // Minimum update frequency (seconds)
    }

    // constants
    /**
     * @dev Denominator for basis points calculations (1 basis point = 0.01%).
     * Used for trailing distance, slippage, and price deviation math.
     * Example:
     *   - trailingDistance = 200 → 2% trailing distance (200 / 10000)
     *   - maxSlippage = 50 → 0.5% max slippage (50 / 10000)
     *   - deviation = 150 → 1.5% price change (150 / 10000)
     */
    uint256 private constant _SLIPPAGE_DENOMINATOR = 10000;

    // storages

    mapping(bytes32 => TrailingStopConfig) public trailingStopConfigs;

    // events

    event TrailingStopConfigUpdated(
        address indexed maker, address indexed makerAssetOracle, uint256 initialStopPrice, uint256 trailingDistance
    );

    event TrailingStopUpdated(
        bytes32 indexed orderHash, uint256 oldStopPrice, uint256 newStopPrice, uint256 currentPrice, address updater
    );

    // modifiers

    constructor() Ownable(msg.sender) {}

    function configureTrailingStop(bytes32 orderHash, TrailingStopConfig calldata config) external {
        address maker = msg.sender;

        if (address(config.makerAssetOracle) == address(0)) {
            revert InvalidMakerAssetOracle();
        }

        if (config.initialStopPrice == 0) {
            revert InvalidTrailingDistance();
        }

        // Minimum trailing distance is 0.5% (50 basis points)
        if (config.trailingDistance < 50) {
            revert InvalidTrailingDistance();
        }

        TrailingStopConfig storage storedConfig = trailingStopConfigs[orderHash];
        storedConfig.makerAssetOracle = config.makerAssetOracle;
        storedConfig.initialStopPrice = config.initialStopPrice;
        storedConfig.trailingDistance = config.trailingDistance;
        storedConfig.currentStopPrice = config.initialStopPrice;
        storedConfig.configuredAt = block.timestamp;
        storedConfig.lastUpdateAt = block.timestamp;
        storedConfig.updateFrequency = config.updateFrequency;

        emit TrailingStopConfigUpdated(
            maker, address(config.makerAssetOracle), config.initialStopPrice, config.trailingDistance
        );
    }

    function updateTrailingStop(bytes32 orderHash) external whenNotPaused {
        TrailingStopConfig storage config = trailingStopConfigs[orderHash];

        // this happens when the order is not configured
        if (config.configuredAt == 0) {
            revert TrailingStopNotConfigured();
        }

        // this happens when the update frequency has not passed/want to update before the frequency
        if (block.timestamp - config.lastUpdateAt < config.updateFrequency) {
            revert InvalidUpdateFrequency();
        }

        uint256 currentPrice = _getCurrentPrice(config.makerAssetOracle);

        // Store old stop price for event emission
        uint256 oldStopPrice = config.currentStopPrice;

        // Calculate and update the trailing stop price
        uint256 newStopPrice = _calculateTrailingStopPrice(currentPrice, config.trailingDistance);
        config.currentStopPrice = newStopPrice;
        config.lastUpdateAt = block.timestamp;

        // Emit event for tracking trailing stop updates
        emit TrailingStopUpdated(orderHash, oldStopPrice, newStopPrice, currentPrice, msg.sender);
    }

    /**
     * @notice Calculates the new trailing stop price based on current market price
     * @dev Trailing stop price = currentPrice - (currentPrice * trailingDistance / 10000)
     * This ensures the stop price follows the market price downward but maintains the trailing distance
     * @param currentPrice The current market price (18 decimals)
     * @param trailingDistance The trailing distance in basis points (e.g., 200 = 2%)
     * @return newStopPrice The calculated trailing stop price (18 decimals)
     */
    function _calculateTrailingStopPrice(uint256 currentPrice, uint256 trailingDistance)
        internal
        pure
        returns (uint256)
    {
        // Calculate the trailing amount: currentPrice * trailingDistance / 10000
        uint256 trailingAmount = (currentPrice * trailingDistance) / _SLIPPAGE_DENOMINATOR;

        // New stop price = current price - trailing amount
        return currentPrice - trailingAmount;
    }

    /**
     * @notice Gets the current price from Chainlink oracle and converts it to 18 decimals
     * @dev Chainlink oracles typically return prices with 8 decimal precision
     * This function converts the 8-decimal price to 18 decimals for consistent handling
     * @param makerAssetOracle The Chainlink price feed oracle
     * @return normalizedPrice The current price converted to 18 decimals
     */
    function _getCurrentPrice(AggregatorV3Interface makerAssetOracle) internal view returns (uint256) {
        (, int256 answer,,,) = makerAssetOracle.latestRoundData();

        // Chainlink oracles return 8 decimal prices, convert to 18 decimals
        // Multiply by 10^10 to convert from 8 decimals to 18 decimals
        return uint256(answer) * 1e10;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _getMakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view override returns (uint256) {
        TrailingStopConfig memory config = trailingStopConfigs[orderHash];

        // if the trailing stop is not configured, return the making amount from the base contract
        if (config.configuredAt == 0) {
            return super._getMakingAmount(
                order, extension, orderHash, taker, takingAmount, remainingMakingAmount, extraData
            );
        }

        // TODO: implement the logic to get the making amount
        return 0;
    }

    function _getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view override returns (uint256) {
        TrailingStopConfig memory config = trailingStopConfigs[orderHash];
        if (config.configuredAt == 0) {
            return super._getTakingAmount(
                order, extension, orderHash, taker, makingAmount, remainingMakingAmount, extraData
            );

            // TODO: implement the logic to get the taking amount
            return 0;
        }
    }

    function preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external override {
        TrailingStopConfig memory config = trailingStopConfigs[orderHash];

        // TODO: Need to decide what to do when no stop triggered
        if (config.configuredAt == 0) {
            revert TrailingStopNotTriggered();
        }

        uint256 currentPrice = _getCurrentPrice(config.makerAssetOracle);

        // TODO: implement the logic to pre-interaction
    }

    function takerInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external whenNotPaused {
        TrailingStopConfig memory config = trailingStopConfigs[orderHash];
        // TODO: implement the logic to taker interaction

        // decode the extra data and agregration router
        (address aggregationRouter, bytes memory swapData) = abi.decode(extraData, (address, bytes));

        IERC20(AddressLib.get(order.makerAsset)).safeTransferFrom(
            AddressLib.get(order.maker), address(this), makingAmount
        );

        // approve to router to spend maker
        IERC20 makerToken = IERC20(AddressLib.get(order.makerAsset));
        makerToken.safeIncreaseAllowance(aggregationRouter, makingAmount);

        //
        makerToken.safeIncreaseAllowance(aggregationRouter, makingAmount);
    }
}
