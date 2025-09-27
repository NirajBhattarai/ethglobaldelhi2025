// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";
import "../interfaces/IOrderMixin.sol";
import "../libraries/OrderBuilderLib.sol";
import "../libraries/TakerTraitsLib.sol";
import "../libraries/MakerTraitsLib.sol";

/**
 * @title OrderBuilderHelper
 * @notice A helper contract that demonstrates how to use OrderBuilderLib
 * @dev This contract provides convenient functions for building orders with various configurations
 */
contract OrderBuilderHelper {
    using OrderBuilderLib for OrderBuilderLib.OrderConfig;
    using OrderBuilderLib for OrderBuilderLib.MakerTraitsConfig;
    using OrderBuilderLib for OrderBuilderLib.OrderExtensionConfig;
    using OrderBuilderLib for OrderBuilderLib.TakerTraitsConfig;
    using TakerTraitsLib for TakerTraits;
    using MakerTraitsLib for MakerTraits;

    /**
     * @notice Creates a basic order with default settings
     * @param maker The maker address
     * @param makerAsset The maker asset address
     * @param takerAsset The taker asset address
     * @param makingAmount The making amount
     * @param takingAmount The taking amount
     * @return order The built order
     */
    function createBasicOrder(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount
    ) external pure returns (IOrderMixin.Order memory order) {
        return OrderBuilderLib.createSimpleOrder(maker, makerAsset, takerAsset, makingAmount, takingAmount);
    }

    /**
     * @notice Creates an order with preInteraction and postInteraction
     * @param maker The maker address
     * @param makerAsset The maker asset address
     * @param takerAsset The taker asset address
     * @param makingAmount The making amount
     * @param takingAmount The taking amount
     * @param preInteraction The pre-interaction contract address
     * @param postInteraction The post-interaction contract address
     * @return order The built order with interactions
     */
    function createOrderWithInteractions(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        address preInteraction,
        address postInteraction
    ) external pure returns (IOrderMixin.Order memory order) {
        return OrderBuilderLib.createOrderWithInteractions(
            maker, makerAsset, takerAsset, makingAmount, takingAmount, preInteraction, postInteraction
        );
    }

    /**
     * @notice Creates an order with AmountGetter support
     * @param maker The maker address
     * @param makerAsset The maker asset address
     * @param takerAsset The taker asset address
     * @param makingAmount The making amount
     * @param takingAmount The taking amount
     * @param amountGetter The AmountGetter contract address
     * @return order The built order with AmountGetter
     */
    function createOrderWithAmountGetter(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        address amountGetter
    ) external pure returns (IOrderMixin.Order memory order) {
        return OrderBuilderLib.createOrderWithAmountGetter(
            maker, makerAsset, takerAsset, makingAmount, takingAmount, amountGetter
        );
    }

    /**
     * @notice Creates a custom order with full configuration
     * @param config The complete order configuration
     * @return order The built order
     */
    function createCustomOrder(OrderBuilderLib.OrderConfig memory config)
        external
        pure
        returns (IOrderMixin.Order memory order)
    {
        return OrderBuilderLib.buildOrder(config);
    }

    /**
     * @notice Creates an RFQ order
     * @param config The order configuration
     * @return order The built RFQ order
     */
    function createRFQOrder(OrderBuilderLib.OrderConfig memory config)
        external
        pure
        returns (IOrderMixin.Order memory order)
    {
        return OrderBuilderLib.buildOrderRFQ(config);
    }

    /**
     * @notice Creates taker traits for order execution
     * @param config The taker traits configuration
     * @return takerTraits The encoded taker traits
     * @return args The encoded arguments
     */
    function createTakerTraits(OrderBuilderLib.TakerTraitsConfig memory config)
        external
        pure
        returns (TakerTraits takerTraits, bytes memory args)
    {
        return OrderBuilderLib.buildTakerTraits(config);
    }

    /**
     * @notice Creates a trailing stop order with all necessary components
     * @param maker The maker address
     * @param makerAsset The maker asset address (e.g., WETH)
     * @param takerAsset The taker asset address (e.g., USDC)
     * @param makingAmount The making amount
     * @param takingAmount The taking amount
     * @param trailingStopContract The trailing stop contract address
     * @param expiry The order expiry timestamp
     * @param nonce The order nonce
     * @return order The built trailing stop order
     */
    function createTrailingStopOrder(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        address trailingStopContract,
        uint256 expiry,
        uint256 nonce
    ) external pure returns (IOrderMixin.Order memory order) {
        OrderBuilderLib.OrderConfig memory config = OrderBuilderLib.OrderConfig({
            maker: maker,
            receiver: address(0),
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: OrderBuilderLib.MakerTraitsConfig({
                allowedSender: address(0),
                shouldCheckEpoch: false,
                allowPartialFill: true,
                allowMultipleFills: true,
                usePermit2: false,
                unwrapWeth: false,
                expiry: expiry,
                nonce: nonce,
                series: 0
            }),
            extension: OrderBuilderLib.OrderExtensionConfig({
                makerAssetSuffix: "",
                takerAssetSuffix: "",
                makingAmountData: abi.encodePacked(trailingStopContract),
                takingAmountData: abi.encodePacked(trailingStopContract),
                predicate: "",
                permit: "",
                preInteraction: abi.encodePacked(trailingStopContract),
                postInteraction: abi.encodePacked(trailingStopContract),
                customData: ""
            })
        });

        return OrderBuilderLib.buildOrder(config);
    }

    /**
     * @notice Creates a stop loss order with AmountGetter and interactions
     * @param maker The maker address
     * @param makerAsset The maker asset address
     * @param takerAsset The taker asset address
     * @param makingAmount The making amount
     * @param takingAmount The taking amount
     * @param stopLossContract The stop loss contract address
     * @param expiry The order expiry timestamp
     * @return order The built stop loss order
     */
    function createStopLossOrder(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        address stopLossContract,
        uint256 expiry
    ) external pure returns (IOrderMixin.Order memory order) {
        OrderBuilderLib.OrderConfig memory config = OrderBuilderLib.OrderConfig({
            maker: maker,
            receiver: address(0),
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: OrderBuilderLib.MakerTraitsConfig({
                allowedSender: address(0),
                shouldCheckEpoch: false,
                allowPartialFill: true,
                allowMultipleFills: true,
                usePermit2: false,
                unwrapWeth: false,
                expiry: expiry,
                nonce: 0,
                series: 0
            }),
            extension: OrderBuilderLib.OrderExtensionConfig({
                makerAssetSuffix: "",
                takerAssetSuffix: "",
                makingAmountData: abi.encodePacked(stopLossContract),
                takingAmountData: abi.encodePacked(stopLossContract),
                predicate: "",
                permit: "",
                preInteraction: abi.encodePacked(stopLossContract),
                postInteraction: abi.encodePacked(stopLossContract),
                customData: ""
            })
        });

        return OrderBuilderLib.buildOrder(config);
    }

    /**
     * @notice Creates taker traits for executing a stop loss order
     * @param aggregationRouter The aggregation router address
     * @param swapData The swap data for the aggregation router
     * @param threshold The threshold amount
     * @return takerTraits The encoded taker traits
     * @return args The encoded arguments
     */
    function createStopLossTakerTraits(address aggregationRouter, bytes memory swapData, uint256 threshold)
        external
        pure
        returns (TakerTraits takerTraits, bytes memory args)
    {
        bytes memory extraData = abi.encode(aggregationRouter, swapData);

        OrderBuilderLib.TakerTraitsConfig memory config = OrderBuilderLib.TakerTraitsConfig({
            makingAmount: false,
            unwrapWeth: false,
            skipMakerPermit: false,
            usePermit2: false,
            target: address(0),
            extension: "",
            interaction: extraData,
            threshold: threshold
        });

        return OrderBuilderLib.buildTakerTraits(config);
    }

    /**
     * @notice Validates that an order has the required interaction flags
     * @param order The order to validate
     * @param requirePreInteraction Whether pre-interaction is required
     * @param requirePostInteraction Whether post-interaction is required
     * @return valid Whether the order has the required interactions
     */
    function validateOrderInteractions(
        IOrderMixin.Order memory order,
        bool requirePreInteraction,
        bool requirePostInteraction
    ) external pure returns (bool valid) {
        MakerTraits makerTraits = order.makerTraits;

        if (requirePreInteraction && !makerTraits.needPreInteractionCall()) {
            return false;
        }

        if (requirePostInteraction && !makerTraits.needPostInteractionCall()) {
            return false;
        }

        return true;
    }

    /**
     * @notice Gets the order hash for a given order
     * @param order The order to hash
     * @return orderHash The order hash
     */
    function getOrderHash(IOrderMixin.Order memory order, bytes32 /* domainSeparator */ )
        external
        pure
        returns (bytes32 orderHash)
    {
        return keccak256(
            abi.encode(
                keccak256(
                    "Order(uint256 salt,address maker,address receiver,address makerAsset,address takerAsset,uint256 makingAmount,uint256 takingAmount,uint256 makerTraits)"
                ),
                order.salt,
                AddressLib.get(order.maker),
                AddressLib.get(order.receiver),
                AddressLib.get(order.makerAsset),
                AddressLib.get(order.takerAsset),
                order.makingAmount,
                order.takingAmount,
                MakerTraits.unwrap(order.makerTraits)
            )
        );
    }
}
