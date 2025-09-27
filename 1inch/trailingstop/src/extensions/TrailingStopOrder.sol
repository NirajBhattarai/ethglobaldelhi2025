// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

// Forge imports
import {console} from "forge-std/console.sol";

// Chainlink imports
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// OpenZeppelin imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
import {LimitOrderProtocol} from "../LimitOrderProtocol.sol";

/**
 * @title TrailingStopOrder
 * @notice A contract that implements the trailing stop order functionality for the 1inch Limit Order Protocol.
 */
contract TrailingStopOrder is AmountGetterBase, Pausable, Ownable, IPreInteraction, ITakerInteraction {
    // libraries
    using Math for uint256;
    using SafeERC20 for IERC20;

    // errors

    error InvalidMakerAssetOracle();
    error InvalidTrailingDistance();
    error TrailingStopNotConfigured();
    error InvalidUpdateFrequency();
    error TrailingStopNotTriggered();
    error SwapExecutionFailed();
    error OnlyKeeper();
    error SlippageExceeded();
    error InvalidLimitOrderProtocol();
    error InvalidOrderType();

    // enums

    enum OrderType {
        SELL, // Sell order: stop loss when price goes down
        BUY // Buy order: stop loss when price goes up

    }

    // structs

    struct TrailingStopConfig {
        AggregatorV3Interface makerAssetOracle;
        uint256 initialStopPrice; // initial stop price in maker asset
        uint256 trailingDistance; // trailing distance in maker asset
        uint256 currentStopPrice; // updated stop price in maker asset
        uint256 configuredAt; // timestamp when the trailing stop was configured
        uint256 lastUpdateAt; // timestamp when the trailing stop was last updated
        uint256 updateFrequency; // Minimum update frequency (seconds)
        uint256 maxSlippage; // Max slippage in basis points
        address keeper; // Keeper address responsible for executing the trailing stop order
        OrderType orderType; // Type of order: SELL or BUY
        uint8 makerAssetDecimals; // Decimals of the maker asset
        uint8 takerAssetDecimals; // Decimals of the taker asset
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
    address public limitOrderProtocol;

    // events

    event TrailingStopConfigUpdated(
        address indexed maker,
        address indexed makerAssetOracle,
        uint256 initialStopPrice,
        uint256 trailingDistance,
        OrderType orderType
    );

    event TrailingStopUpdated(
        bytes32 indexed orderHash, uint256 oldStopPrice, uint256 newStopPrice, uint256 currentPrice, address updater
    );

    event TrailingStopTriggered(
        bytes32 indexed orderHash, address indexed taker, uint256 takerAssetBalance, uint256 stopPrice
    );

    constructor(address _limitOrderProtocol) Ownable(msg.sender) {
        if (_limitOrderProtocol == address(0)) {
            revert InvalidLimitOrderProtocol();
        }
        limitOrderProtocol = _limitOrderProtocol;
    }

    // modifiers
    modifier onlyKeeper(bytes32 orderHash) {
        TrailingStopConfig memory config = trailingStopConfigs[orderHash];
        if (config.keeper != address(0) && config.keeper != msg.sender) {
            revert OnlyKeeper();
        }
        _;
    }

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

        // Validate max slippage (maximum 10% = 1000 basis points)
        if (config.maxSlippage > 1000) {
            revert InvalidTrailingDistance();
        }

        // Validate order type
        if (config.orderType != OrderType.SELL && config.orderType != OrderType.BUY) {
            revert InvalidOrderType();
        }

        TrailingStopConfig storage storedConfig = trailingStopConfigs[orderHash];
        storedConfig.makerAssetOracle = config.makerAssetOracle;
        storedConfig.initialStopPrice = config.initialStopPrice;
        storedConfig.trailingDistance = config.trailingDistance;
        storedConfig.currentStopPrice = config.initialStopPrice;
        storedConfig.configuredAt = block.timestamp;
        storedConfig.lastUpdateAt = block.timestamp;
        storedConfig.updateFrequency = config.updateFrequency;
        storedConfig.maxSlippage = config.maxSlippage;
        storedConfig.keeper = config.keeper;
        storedConfig.orderType = config.orderType;
        
        // Store decimal information - these will be set when the order is processed
        // Default to 0, will be updated in takerInteraction when order is filled
        storedConfig.makerAssetDecimals = 0;
        storedConfig.takerAssetDecimals = 0;

        emit TrailingStopConfigUpdated(
            maker, address(config.makerAssetOracle), config.initialStopPrice, config.trailingDistance, config.orderType
        );
    }

    function updateTrailingStop(bytes32 orderHash) external whenNotPaused onlyKeeper(orderHash) {
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

        // Calculate and update the trailing stop price based on order type
        uint256 newStopPrice = _calculateTrailingStopPrice(currentPrice, config.trailingDistance, config.orderType);
        config.currentStopPrice = newStopPrice;
        config.lastUpdateAt = block.timestamp;

        // Emit event for tracking trailing stop updates
        emit TrailingStopUpdated(orderHash, oldStopPrice, newStopPrice, currentPrice, msg.sender);
    }

    /**
     * @notice Calculates the new trailing stop price based on current market price and order type
     * @dev For SELL orders: stop price = currentPrice - (currentPrice * trailingDistance / 10000)
     *      For BUY orders: stop price = currentPrice + (currentPrice * trailingDistance / 10000)
     * @param currentPrice The current market price (18 decimals)
     * @param trailingDistance The trailing distance in basis points (e.g., 200 = 2%)
     * @param orderType The type of order (SELL or BUY)
     * @return newStopPrice The calculated trailing stop price (18 decimals)
     */
    function _calculateTrailingStopPrice(uint256 currentPrice, uint256 trailingDistance, OrderType orderType)
        internal
        pure
        returns (uint256)
    {
        // Calculate the trailing amount: currentPrice * trailingDistance / 10000
        uint256 trailingAmount = (currentPrice * trailingDistance) / _SLIPPAGE_DENOMINATOR;

        if (orderType == OrderType.SELL) {
            // For sell orders: stop price = current price - trailing amount
            return currentPrice - trailingAmount;
        } else {
            // For buy orders: stop price = current price + trailing amount
            return currentPrice + trailingAmount;
        }
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

    /**
     * @notice Normalizes a price to 18 decimals based on maker and taker asset decimals
     * @dev This function converts a price from the natural decimals of the assets to 18 decimals
     * @param takingAmount The taking amount in taker asset decimals
     * @param makingAmount The making amount in maker asset decimals
     * @param takerAssetDecimals The decimals of the taker asset
     * @param makerAssetDecimals The decimals of the maker asset
     * @return normalizedPrice The price normalized to 18 decimals
     */
    function _normalizePrice(
        uint256 takingAmount,
        uint256 makingAmount,
        uint8 takerAssetDecimals,
        uint8 makerAssetDecimals
    ) internal pure returns (uint256) {
        // Calculate the decimal difference needed to normalize to 18 decimals
        // Price = takingAmount / makingAmount
        // To normalize to 18 decimals: (takingAmount * 10^(18 - takerDecimals)) / (makingAmount * 10^(18 - makerDecimals))
        // Simplified: (takingAmount * 10^(18 - takerDecimals + makerDecimals)) / makingAmount
        
        // Normalize both amounts to 18 decimals then calculate price
        uint256 normalizedTakingAmount = takingAmount * (10 ** (18 - takerAssetDecimals));
        uint256 normalizedMakingAmount = makingAmount * (10 ** (18 - makerAssetDecimals));
        
        return (normalizedTakingAmount * 1e18) / normalizedMakingAmount;
    }

    /**
     * @notice Calculates the slippage between expected and actual execution price
     * @dev Slippage = |actualPrice - expectedPrice| / expectedPrice * 10000 (basis points)
     * @param expectedPrice The expected execution price (18 decimals)
     * @param actualPrice The actual execution price (18 decimals)
     * @return slippageBps The slippage in basis points
     */
    function _calculateSlippage(uint256 expectedPrice, uint256 actualPrice) internal pure returns (uint256) {
        if (expectedPrice == 0) return 0;

        uint256 priceDifference =
            expectedPrice > actualPrice ? expectedPrice - actualPrice : actualPrice - expectedPrice;

        return (priceDifference * _SLIPPAGE_DENOMINATOR) / expectedPrice;
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

        // Get current price from oracle
        uint256 currentPrice = _getCurrentPrice(config.makerAssetOracle);
        
        // Check if trailing stop is triggered
        bool isTriggered = false;
        if (config.orderType == OrderType.SELL) {
            // For sell orders: trigger when current price <= stop price
            isTriggered = currentPrice <= config.currentStopPrice;
        } else {
            // For buy orders: trigger when current price >= stop price
            isTriggered = currentPrice >= config.currentStopPrice;
        }

        // If not triggered, return 0 (order should not execute)
        if (!isTriggered) {
            return 0;
        }

        // Calculate making amount based on current price and decimal handling
        return _calculateMakingAmountWithDecimals(takingAmount, currentPrice, config);
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
        }

        // Get current price from oracle
        uint256 currentPrice = _getCurrentPrice(config.makerAssetOracle);
        
        // Check if trailing stop is triggered
        bool isTriggered = false;
        if (config.orderType == OrderType.SELL) {
            // For sell orders: trigger when current price <= stop price
            isTriggered = currentPrice <= config.currentStopPrice;
        } else {
            // For buy orders: trigger when current price >= stop price
            isTriggered = currentPrice >= config.currentStopPrice;
        }

        // If not triggered, return max value (order should not execute)
        if (!isTriggered) {
            return type(uint256).max;
        }

        // Calculate taking amount based on current price and decimal handling
        return _calculateTakingAmountWithDecimals(makingAmount, currentPrice, config);
    }

    function preInteraction(
        IOrderMixin.Order calldata, /* order */
        bytes calldata, /* extension */
        bytes32 orderHash,
        address, /* taker */
        uint256, /* makingAmount */
        uint256, /* takingAmount */
        uint256, /* remainingMakingAmount */
        bytes calldata /* extraData */
    ) external view override {
        TrailingStopConfig memory config = trailingStopConfigs[orderHash];

        console.log("TrailingStopOrder: preInteraction called");
        console.log("orderHash:");
        console.logBytes32(orderHash);
        console.log("config.configuredAt:");
        console.logUint(config.configuredAt);

        // TODO: Need to decide what to do when no stop triggered
        if (config.configuredAt == 0) {
            revert TrailingStopNotTriggered();
        }

        // TODO: implement the logic to pre-interaction
    }

    function takerInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata, /* extension */
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256, /* remainingMakingAmount */
        bytes calldata extraData
    ) external whenNotPaused {
        // Restrict to 1inch Limit Order Protocol
        if (msg.sender != limitOrderProtocol) {
            revert("Only 1inch LOP can call");
        }

        console.log("TrailingStopOrder: takerInteraction called");
        console.log("orderHash:");
        console.logBytes32(orderHash);
        console.log("taker:");
        console.logAddress(taker);
        console.log("makingAmount:");
        console.logUint(makingAmount);
        console.log("takingAmount:");
        console.logUint(takingAmount);

        TrailingStopConfig memory config = trailingStopConfigs[orderHash];
        if (config.configuredAt == 0) {
            revert TrailingStopNotConfigured();
        }

        // Get current price from Chainlink oracle (18 decimals)
        uint256 currentPrice = _getCurrentPrice(config.makerAssetOracle);

        // Check if trailing stop is triggered based on order type
        bool isTriggered = false;
        if (config.orderType == OrderType.SELL) {
            // For sell orders: trigger when current price <= stop price
            isTriggered = currentPrice <= config.currentStopPrice;
        } else {
            // For buy orders: trigger when current price >= stop price
            isTriggered = currentPrice >= config.currentStopPrice;
        }

        if (!isTriggered) {
            revert TrailingStopNotTriggered();
        }

        // Get decimal information from the assets and store them if not already set
        TrailingStopConfig storage configStorage = trailingStopConfigs[orderHash];
        if (configStorage.makerAssetDecimals == 0 || configStorage.takerAssetDecimals == 0) {
            configStorage.makerAssetDecimals = IERC20Metadata(AddressLib.get(order.makerAsset)).decimals();
            configStorage.takerAssetDecimals = IERC20Metadata(AddressLib.get(order.takerAsset)).decimals();
        }

        // Calculate expected price using normalized decimals
        uint256 expectedPrice = _normalizePrice(
            takingAmount,
            makingAmount,
            configStorage.takerAssetDecimals,
            configStorage.makerAssetDecimals
        );
        
        uint256 slippage = _calculateSlippage(expectedPrice, currentPrice);
        if (slippage > config.maxSlippage) {
            revert SlippageExceeded();
        }

        // Decode extraData for swap (if any)
        (address aggregationRouter, bytes memory swapData) = abi.decode(extraData, (address, bytes));

        // Transfer maker assets (WBTC) to taker
        IERC20 makerToken = IERC20(AddressLib.get(order.makerAsset));
        makerToken.safeTransferFrom(AddressLib.get(order.maker), taker, makingAmount);

        // If swapData is provided, execute swap via Aggregation Router
        if (swapData.length > 0) {
            // Approve Aggregation Router to spend taker assets (USDC, already transferred by LOP)
            IERC20 takerToken = IERC20(AddressLib.get(order.takerAsset));
            takerToken.approve(aggregationRouter, takingAmount);

            // Execute swap
            (bool success,) = aggregationRouter.call{value: 0}(swapData);
            if (!success) {
                revert SwapExecutionFailed();
            }

            // Transfer swapped assets (or remaining taker assets) to maker
            uint256 takerTokenBalance = takerToken.balanceOf(address(this));
            takerToken.safeTransfer(AddressLib.get(order.maker), takerTokenBalance);
        } else {
            // Direct transfer of taker assets (USDC) to maker
            IERC20 takerToken = IERC20(AddressLib.get(order.takerAsset));
            takerToken.safeTransfer(AddressLib.get(order.maker), takingAmount);
        }

        // Emit event
        emit TrailingStopTriggered(orderHash, taker, takingAmount, config.currentStopPrice);
    }

    /**
     * @notice Calculates making amount with proper decimal handling
     * @dev Converts taking amount to making amount based on current price
     * @param takingAmount The amount being taken (in taker asset decimals)
     * @param currentPrice The current market price (18 decimals)
     * @param config The trailing stop configuration
     * @return makingAmount The calculated making amount (in maker asset decimals)
     */
    function _calculateMakingAmountWithDecimals(
        uint256 takingAmount,
        uint256 currentPrice,
        TrailingStopConfig memory config
    ) internal pure returns (uint256) {
        // Normalize taking amount to 18 decimals
        uint256 normalizedTakingAmount = takingAmount;
        if (config.takerAssetDecimals < 18) {
            normalizedTakingAmount = takingAmount * (10 ** (18 - config.takerAssetDecimals));
        } else if (config.takerAssetDecimals > 18) {
            normalizedTakingAmount = takingAmount / (10 ** (config.takerAssetDecimals - 18));
        }

        // Calculate making amount in 18 decimals: takingAmount / currentPrice
        uint256 makingAmount18 = (normalizedTakingAmount * 1e18) / currentPrice;

        // Convert back to maker asset decimals
        if (config.makerAssetDecimals < 18) {
            return makingAmount18 / (10 ** (18 - config.makerAssetDecimals));
        } else if (config.makerAssetDecimals > 18) {
            return makingAmount18 * (10 ** (config.makerAssetDecimals - 18));
        }

        return makingAmount18;
    }

    /**
     * @notice Calculates taking amount with proper decimal handling
     * @dev Converts making amount to taking amount based on current price
     * @param makingAmount The amount being made (in maker asset decimals)
     * @param currentPrice The current market price (18 decimals)
     * @param config The trailing stop configuration
     * @return takingAmount The calculated taking amount (in taker asset decimals)
     */
    function _calculateTakingAmountWithDecimals(
        uint256 makingAmount,
        uint256 currentPrice,
        TrailingStopConfig memory config
    ) internal pure returns (uint256) {
        // Normalize making amount to 18 decimals
        uint256 normalizedMakingAmount = makingAmount;
        if (config.makerAssetDecimals < 18) {
            normalizedMakingAmount = makingAmount * (10 ** (18 - config.makerAssetDecimals));
        } else if (config.makerAssetDecimals > 18) {
            normalizedMakingAmount = makingAmount / (10 ** (config.makerAssetDecimals - 18));
        }

        // Calculate taking amount in 18 decimals: makingAmount * currentPrice
        uint256 takingAmount18 = (normalizedMakingAmount * currentPrice) / 1e18;

        // Convert back to taker asset decimals
        if (config.takerAssetDecimals < 18) {
            return takingAmount18 / (10 ** (18 - config.takerAssetDecimals));
        } else if (config.takerAssetDecimals > 18) {
            return takingAmount18 * (10 ** (config.takerAssetDecimals - 18));
        }

        return takingAmount18;
    }
}
