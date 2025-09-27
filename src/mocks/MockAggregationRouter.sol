// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";

/**
 * @title MockAggregationRouter
 * @notice Mock implementation of 1inch AggregationRouter for testing purposes
 * @dev This contract simulates the behavior of the 1inch AggregationRouter
 *      by handling token swaps and transfers between maker and taker
 */
contract MockAggregationRouter {
    using SafeERC20 for IERC20;

    // Events
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );

    event TransferExecuted(address indexed from, address indexed to, address indexed token, uint256 amount);

    // State variables
    mapping(address => mapping(address => uint256)) public exchangeRates; // tokenA => tokenB => rate (in 18 decimals)

    address public owner;

    // Errors
    error Unauthorized();
    error InvalidExchangeRate();
    error InsufficientBalance();
    error TransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Set exchange rate between two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param rate Exchange rate (tokenA per tokenB in 18 decimals)
     */
    function setExchangeRate(address tokenA, address tokenB, uint256 rate) external onlyOwner {
        exchangeRates[tokenA][tokenB] = rate;
        exchangeRates[tokenB][tokenA] = 1e36 / rate; // Inverse rate
        console.log("Set exchange rate:", rate);
        console.log("TokenA:", tokenA);
        console.log("TokenB:", tokenB);
    }

    /**
     * @notice Execute a swap between tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param recipient Address to receive output tokens
     * @return amountOut Amount of output tokens received
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address recipient)
        external
        returns (uint256 amountOut)
    {
        console.log("MockAggregationRouter: swap called");
        console.log("TokenIn:", tokenIn);
        console.log("TokenOut:", tokenOut);
        console.log("AmountIn:", amountIn);
        console.log("Recipient:", recipient);

        // Get exchange rate
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) revert InvalidExchangeRate();

        // Calculate output amount
        amountOut = (amountIn * rate) / 1e18;

        console.log("Exchange rate:", rate);
        console.log("AmountOut:", amountOut);

        // Transfer input tokens from caller to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        console.log("Transferred input tokens to router");

        // Transfer output tokens from this contract to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
        console.log("Transferred output tokens to recipient");

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);

        return amountOut;
    }

    /**
     * @notice Execute a direct transfer from taker to maker
     * @param takerToken Token address that taker is providing
     * @param makerToken Token address that maker is providing
     * @param takerAmount Amount of taker tokens
     * @param makerAmount Amount of maker tokens
     * @param takerAddress Address of the taker
     * @param makerAddress Address of the maker
     */
    function executeDirectTransfer(
        address takerToken,
        address makerToken,
        uint256 takerAmount,
        uint256 makerAmount,
        address takerAddress,
        address makerAddress
    ) internal {
        console.log("MockAggregationRouter: executeDirectTransfer called");
        console.log("TakerToken:", takerToken);
        console.log("MakerToken:", makerToken);
        console.log("TakerAmount:", takerAmount);
        console.log("MakerAmount:", makerAmount);
        console.log("TakerAddress:", takerAddress);
        console.log("MakerAddress:", makerAddress);

        // Transfer maker tokens from msg.sender (TrailingStopOrder contract) to taker
        // The TrailingStopOrder contract already has the maker's tokens
        console.log("About to transfer maker tokens from:", msg.sender);
        console.log("To taker:", takerAddress);
        console.log("Amount:", makerAmount);

        uint256 allowance = IERC20(makerToken).allowance(msg.sender, address(this));
        console.log("Allowance:", allowance);

        IERC20(makerToken).safeTransferFrom(msg.sender, takerAddress, makerAmount);
        console.log("Transferred maker tokens to taker");

        // Note: The TrailingStopOrder contract will handle the taker token transfer
        // from taker to maker in its own code after this function returns

        emit TransferExecuted(msg.sender, takerAddress, makerToken, makerAmount);
    }

    /**
     * @notice Handle swap with custom calldata (for compatibility with 1inch interface)
     * @param swapData Encoded swap parameters
     */
    function handleSwap(bytes calldata swapData) public {
        console.log("MockAggregationRouter: handleSwap called with calldata");

        // Decode swap data
        (
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            address recipient,
            address takerAddress,
            address makerAddress
        ) = abi.decode(swapData, (address, address, uint256, address, address, address));

        console.log("Decoded swap data:");
        console.log("TokenIn:", tokenIn);
        console.log("TokenOut:", tokenOut);
        console.log("AmountIn:", amountIn);
        console.log("Recipient:", recipient);
        console.log("TakerAddress:", takerAddress);
        console.log("MakerAddress:", makerAddress);

        // Execute the swap
        uint256 amountOut = this.swap(tokenIn, tokenOut, amountIn, recipient);

        console.log("Swap completed with amountOut:", amountOut);
    }

    /**
     * @notice Handle direct transfer with custom calldata
     * @param transferData Encoded transfer parameters
     */
    function handleDirectTransfer(bytes calldata transferData) public {
        console.log("MockAggregationRouter: handleDirectTransfer called with calldata");

        // Decode transfer data
        (
            address takerToken,
            address makerToken,
            uint256 takerAmount,
            uint256 makerAmount,
            address takerAddress,
            address makerAddress
        ) = abi.decode(transferData, (address, address, uint256, uint256, address, address));

        console.log("Decoded transfer data:");
        console.log("TakerToken:", takerToken);
        console.log("MakerToken:", makerToken);
        console.log("TakerAmount:", takerAmount);
        console.log("MakerAmount:", makerAmount);
        console.log("TakerAddress:", takerAddress);
        console.log("MakerAddress:", makerAddress);

        // Execute direct transfer
        executeDirectTransfer(takerToken, makerToken, takerAmount, makerAmount, takerAddress, makerAddress);

        console.log("Direct transfer completed");
    }

    /**
     * @notice Generic call handler for compatibility
     * @param data Encoded function call data
     */
    function handleCall(bytes calldata data) external {
        console.log("MockAggregationRouter: handleCall called");

        // Check function selector
        bytes4 selector = bytes4(data[:4]);

        if (selector == this.handleSwap.selector) {
            bytes calldata swapData = data[4:];
            handleSwap(swapData);
        } else if (selector == this.handleDirectTransfer.selector) {
            bytes calldata transferData = data[4:];
            handleDirectTransfer(transferData);
        } else {
            console.log("Unknown function selector, defaulting to direct transfer");
            // Default to direct transfer for compatibility
            handleDirectTransfer(data[4:]);
        }
    }

    /**
     * @notice Emergency function to withdraw tokens
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner, amount);
        console.log("Emergency withdrawal:", amount, "of", token);
    }

    /**
     * @notice Get exchange rate between two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return rate Exchange rate (tokenA per tokenB in 18 decimals)
     */
    function getExchangeRate(address tokenA, address tokenB) external view returns (uint256 rate) {
        return exchangeRates[tokenA][tokenB];
    }
}
