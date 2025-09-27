// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

// Forge imports
import {console} from "forge-std/console.sol";

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
        address indexed maker, address indexed makerAssetOracle, uint256 initialStopPrice, uint256 trailingDistance
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

        emit TrailingStopConfigUpdated(
            maker, address(config.makerAssetOracle), config.initialStopPrice, config.trailingDistance
        );
    }

    function updateTrailingStop(bytes32 orderHash) external whenNotPaused onlyKeeper(orderHash) {
        TrailingStopConfig storage config = trailingStopConfigs[orderHash];

        if (msg.sender != config.keeper) {
            revert OnlyKeeper();
        }

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
        }

        // TODO: implement the logic to get the taking amount
        return 0;
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
        if (currentPrice >= config.currentStopPrice) {
            revert TrailingStopNotTriggered();
        }

        // Calculate expected price: takingAmount (USDC, 6 decimals) / makingAmount (WBTC, 8 decimals)
        // Normalize to 18 decimals: (takingAmount * 1e12) / makingAmount
        uint256 expectedPrice = (takingAmount * 1e12) / makingAmount;
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
}
