// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TrailingStopOrder} from "../src/extensions/TrailingStopOrder.sol";
import {LimitOrderProtocol} from "../src/LimitOrderProtocol.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "@1inch/solidity-utils/interfaces/IWETH.sol";
import {IOrderMixin} from "../src/interfaces/IOrderMixin.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";
import {MakerTraits, MakerTraitsLib} from "../src/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "../src/libraries/TakerTraitsLib.sol";

contract OrderFillMainnetTest is Test {
    // constants

    // Mainnet addresses
    address constant BTC_USD_ORACLE = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant AGGREGATION_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    // ============ State Variables ============
    TrailingStopOrder public trailingStopOrder;
    LimitOrderProtocol public limitOrderProtocol;

    // Test accounts
    address public maker;
    address public taker;

    // ============ Setup ============
    function setUp() public {
        // Deploy LimitOrderProtocol contract
        limitOrderProtocol = new LimitOrderProtocol(IWETH(WETH));

        // Deploy TrailingStopOrder contract with LimitOrderProtocol
        trailingStopOrder = new TrailingStopOrder(address(limitOrderProtocol));

        // Setup test accounts - use addresses that correspond to known private keys
        uint256 makerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // First anvil private key
        maker = vm.addr(makerPrivateKey);
        taker = makeAddr("taker");

        // Fund accounts with ETH
        vm.deal(maker, 100 ether);
        vm.deal(taker, 100 ether);

        // Fund maker with WBTC using deal
        deal(WBTC, maker, 1e8); // 1 WBTC (8 decimals)

        // Fund taker with USDC using deal
        deal(USDC, taker, 120000e6); // 120k USDC (6 decimals)

        // Approve contracts
        vm.startPrank(maker);
        IERC20(WBTC).approve(address(limitOrderProtocol), 1e8);
        IERC20(WBTC).approve(address(trailingStopOrder), 1e8);
        vm.stopPrank();

        vm.startPrank(taker);
        IERC20(USDC).approve(address(limitOrderProtocol), 120000e6);
        IERC20(USDC).approve(address(trailingStopOrder), 120000e6);
        vm.stopPrank();
    }

    // ============ Helper Functions ============
    function createTakerInteractionCalldata(
        IOrderMixin.Order memory orderData,
        bytes32 orderHash,
        address takerAddress,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            TrailingStopOrder.takerInteraction.selector,
            orderData,
            "", // extension
            orderHash,
            takerAddress,
            makingAmount,
            takingAmount,
            remainingMakingAmount,
            abi.encode(AGGREGATION_ROUTER, "") // No swap for simplicity
        );
    }

    // Create proper signature using vm.sign with known private key
    function createValidSignature(address signer, bytes32 orderHash) internal returns (bytes32 r, bytes32 vs) {
        // Use the same private key that was used to generate the maker address
        uint256 privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // First anvil private key
        (uint8 v, bytes32 r_raw, bytes32 s) = vm.sign(privateKey, orderHash);
        r = r_raw;
        // For vs format: v is 27 or 28, so we need to subtract 27 and shift left by 255 bits
        vs = bytes32((uint256(v - 27) << 255) | uint256(s));
    }

    // ============ Main Test ============
    function testFillTrailingStopOrderViaProtocol() public {
        console.log("=== Starting BTC/USDC Trailing Stop Order Fill Test with Real Mainnet Data ===");

        // Use real mainnet BTC/USD oracle
        AggregatorV3Interface btcOracle = AggregatorV3Interface(BTC_USD_ORACLE);

        // Get current BTC price from mainnet oracle
        (, int256 currentPrice,,,) = btcOracle.latestRoundData();
        uint256 btcPrice = uint256(currentPrice); // Price in 8 decimals

        console.log("Current BTC price:", btcPrice / 1e8, "USD");

        // 1. Create order with realistic amounts based on current price
        uint256 wbtcAmount = 1e8; // 1 WBTC (8 decimals)
        uint256 usdcAmount = (btcPrice * 1e6) / 1e8; // Convert BTC price to USDC amount (6 decimals)

        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: uint256(keccak256(abi.encodePacked("mainnet_order", maker, block.timestamp))) & ((1 << 160) - 1),
            maker: Address.wrap(uint256(uint160(maker))),
            receiver: Address.wrap(uint256(uint160(address(0)))),
            makerAsset: Address.wrap(uint256(uint160(WBTC))),
            takerAsset: Address.wrap(uint256(uint160(USDC))),
            makingAmount: wbtcAmount,
            takingAmount: usdcAmount,
            makerTraits: MakerTraits.wrap(1 << 251) // POST_INTERACTION_CALL_FLAG (public order)
        });

        // Get proper order hash from LimitOrderProtocol
        bytes32 orderHash = limitOrderProtocol.hashOrder(order);

        // 2. Configure trailing stop with real oracle
        TrailingStopOrder.TrailingStopConfig memory config = TrailingStopOrder.TrailingStopConfig({
            makerAssetOracle: btcOracle, // Use real mainnet oracle
            initialStopPrice: (btcPrice * 9) / 10, // 90% of current price
            trailingDistance: 200, // 2%
            currentStopPrice: (btcPrice * 9) / 10,
            configuredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            updateFrequency: 300,
            maxSlippage: 100, // 1%
            maxPriceDeviation: 500, // 5% max deviation from TWAP
            twapWindow: 900, // 15 minutes TWAP window
            keeper: address(0),
            orderType: TrailingStopOrder.OrderType.SELL,
            makerAssetDecimals: 0, // Will be set automatically
            takerAssetDecimals: 0 // Will be set automatically
        });

        vm.prank(maker);
        trailingStopOrder.configureTrailingStop(orderHash, config);

        // 3. Update trailing stop
        vm.warp(block.timestamp + 600);
        vm.prank(taker);
        trailingStopOrder.updateTrailingStop(orderHash);

        // 4. Prepare interaction data
        bytes memory interaction =
            createTakerInteractionCalldata(order, orderHash, taker, wbtcAmount, usdcAmount, wbtcAmount);

        // 6. Create valid signature using vm.sign
        (bytes32 r, bytes32 vs) = createValidSignature(maker, orderHash);
        TakerTraits takerTraits = TakerTraits.wrap(1 << 251); // _ARGS_HAS_TARGET flag

        vm.prank(taker);
        (uint256 makingAmount, uint256 takingAmount, bytes32 filledOrderHash) =
            limitOrderProtocol.fillOrderArgs(order, r, vs, usdcAmount, takerTraits, interaction);

        console.log("Test completed - using real mainnet BTC price:", btcPrice / 1e8, "USD");
        console.log("Order filled successfully - Making amount:", makingAmount, "Taking amount:", takingAmount);
    }
}
