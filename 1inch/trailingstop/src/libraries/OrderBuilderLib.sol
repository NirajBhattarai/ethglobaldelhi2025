// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import {Address, AddressLib} from "@1inch/solidity-utils/libraries/AddressLib.sol";
import "../interfaces/IOrderMixin.sol";
import "./MakerTraitsLib.sol";
import "./TakerTraitsLib.sol";

/**
 * @title OrderBuilderLib
 * @notice A library for building orders with preInteraction and postInteraction support
 * @dev This library provides utilities to construct orders with various interaction types
 *      following the 1inch Limit Order Protocol patterns
 */
library OrderBuilderLib {
    using MakerTraitsLib for MakerTraits;
    using TakerTraitsLib for TakerTraits;

    // Constants for interaction flags
    uint256 private constant _NO_PARTIAL_FILLS_FLAG = 1 << 255;
    uint256 private constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;
    uint256 private constant _NEED_PREINTERACTION_FLAG = 1 << 252;
    uint256 private constant _NEED_POSTINTERACTION_FLAG = 1 << 251;
    uint256 private constant _NEED_EPOCH_CHECK_FLAG = 1 << 250;
    uint256 private constant _HAS_EXTENSION_FLAG = 1 << 249;
    uint256 private constant _USE_PERMIT2_FLAG = 1 << 248;
    uint256 private constant _UNWRAP_WETH_FLAG = 1 << 247;

    // Constants for maker traits bit positions
    uint256 private constant _ALLOWED_SENDER_MASK = type(uint80).max;
    uint256 private constant _EXPIRATION_OFFSET = 80;
    uint256 private constant _EXPIRATION_MASK = type(uint40).max;
    uint256 private constant _NONCE_OR_EPOCH_OFFSET = 120;
    uint256 private constant _NONCE_OR_EPOCH_MASK = type(uint40).max;
    uint256 private constant _SERIES_OFFSET = 160;
    uint256 private constant _SERIES_MASK = type(uint40).max;

    // Constants for taker traits
    uint256 private constant _MAKER_AMOUNT_FLAG = 1 << 255;
    uint256 private constant _UNWRAP_WETH_FLAG_TAKER = 1 << 254;
    uint256 private constant _SKIP_ORDER_PERMIT_FLAG = 1 << 253;
    uint256 private constant _USE_PERMIT2_FLAG_TAKER = 1 << 252;
    uint256 private constant _ARGS_HAS_TARGET = 1 << 251;
    uint256 private constant _ARGS_EXTENSION_LENGTH_OFFSET = 224;
    uint256 private constant _ARGS_EXTENSION_LENGTH_MASK = 0xffffff;
    uint256 private constant _ARGS_INTERACTION_LENGTH_OFFSET = 200;
    uint256 private constant _ARGS_INTERACTION_LENGTH_MASK = 0xffffff;

    /**
     * @notice Configuration for building maker traits
     */
    struct MakerTraitsConfig {
        address allowedSender;
        bool shouldCheckEpoch;
        bool allowPartialFill;
        bool allowMultipleFills;
        bool usePermit2;
        bool unwrapWeth;
        uint256 expiry;
        uint256 nonce;
        uint256 series;
    }

    /**
     * @notice Configuration for building taker traits
     */
    struct TakerTraitsConfig {
        bool makingAmount;
        bool unwrapWeth;
        bool skipMakerPermit;
        bool usePermit2;
        address target;
        bytes extension;
        bytes interaction;
        uint256 threshold;
    }

    /**
     * @notice Configuration for order extensions
     */
    struct OrderExtensionConfig {
        bytes makerAssetSuffix;
        bytes takerAssetSuffix;
        bytes makingAmountData;
        bytes takingAmountData;
        bytes predicate;
        bytes permit;
        bytes preInteraction;
        bytes postInteraction;
        bytes customData;
    }

    /**
     * @notice Configuration for building a complete order
     */
    struct OrderConfig {
        address maker;
        address receiver;
        address makerAsset;
        address takerAsset;
        uint256 makingAmount;
        uint256 takingAmount;
        MakerTraitsConfig makerTraits;
        OrderExtensionConfig extension;
    }

    /**
     * @notice Builds maker traits from configuration
     * @param config The maker traits configuration
     * @return makerTraits The encoded maker traits
     */
    function buildMakerTraits(MakerTraitsConfig memory config) internal pure returns (MakerTraits) {
        uint256 traits = 0;

        // Set flags
        if (!config.allowPartialFill) {
            traits |= _NO_PARTIAL_FILLS_FLAG;
        }
        if (config.allowMultipleFills) {
            traits |= _ALLOW_MULTIPLE_FILLS_FLAG;
        }
        if (config.shouldCheckEpoch) {
            traits |= _NEED_EPOCH_CHECK_FLAG;
        }
        if (config.usePermit2) {
            traits |= _USE_PERMIT2_FLAG;
        }
        if (config.unwrapWeth) {
            traits |= _UNWRAP_WETH_FLAG;
        }

        // Set low bits: allowed sender, expiration, nonce, series
        traits |= uint256(uint160(config.allowedSender)) & _ALLOWED_SENDER_MASK;
        traits |= (config.expiry & _EXPIRATION_MASK) << _EXPIRATION_OFFSET;
        traits |= (config.nonce & _NONCE_OR_EPOCH_MASK) << _NONCE_OR_EPOCH_OFFSET;
        traits |= (config.series & _SERIES_MASK) << _SERIES_OFFSET;

        return MakerTraits.wrap(traits);
    }

    /**
     * @notice Builds taker traits from configuration
     * @param config The taker traits configuration
     * @return takerTraits The encoded taker traits
     * @return args The encoded arguments
     */
    function buildTakerTraits(TakerTraitsConfig memory config)
        internal
        pure
        returns (TakerTraits takerTraits, bytes memory args)
    {
        uint256 traits = config.threshold;

        // Set flags
        if (config.makingAmount) {
            traits |= _MAKER_AMOUNT_FLAG;
        }
        if (config.unwrapWeth) {
            traits |= _UNWRAP_WETH_FLAG_TAKER;
        }
        if (config.skipMakerPermit) {
            traits |= _SKIP_ORDER_PERMIT_FLAG;
        }
        if (config.usePermit2) {
            traits |= _USE_PERMIT2_FLAG_TAKER;
        }
        if (config.target != address(0)) {
            traits |= _ARGS_HAS_TARGET;
        }

        // Set extension and interaction lengths
        traits |= (config.extension.length / 2) << _ARGS_EXTENSION_LENGTH_OFFSET;
        traits |= (config.interaction.length / 2) << _ARGS_INTERACTION_LENGTH_OFFSET;

        // Build args
        args = abi.encodePacked(config.target, config.extension, config.interaction);

        takerTraits = TakerTraits.wrap(traits);
    }

    /**
     * @notice Builds order extension from configuration
     * @param config The extension configuration
     * @return extension The encoded extension data
     * @return hasExtension Whether the order has extension data
     */
    function buildOrderExtension(OrderExtensionConfig memory config)
        internal
        pure
        returns (bytes memory extension, bool hasExtension)
    {
        bytes[] memory allInteractions = new bytes[](8);
        allInteractions[0] = config.makerAssetSuffix;
        allInteractions[1] = config.takerAssetSuffix;
        allInteractions[2] = config.makingAmountData;
        allInteractions[3] = config.takingAmountData;
        allInteractions[4] = config.predicate;
        allInteractions[5] = config.permit;
        allInteractions[6] = config.preInteraction;
        allInteractions[7] = config.postInteraction;

        // Calculate total length
        uint256 totalLength = config.customData.length;
        for (uint256 i = 0; i < allInteractions.length; i++) {
            totalLength += allInteractions[i].length;
        }

        if (totalLength == 0) {
            return ("", false);
        }

        // Calculate offsets
        uint256 offsets = 0;
        uint256 cumulativeLength = 0;

        for (uint256 i = 0; i < allInteractions.length; i++) {
            uint256 length = allInteractions[i].length;
            if (length > 0) {
                length = length / 2 - 1; // Convert to word count minus 1
            }
            offsets |= (length << (32 * i));
            cumulativeLength += allInteractions[i].length;
        }

        // Concatenate all interactions
        bytes memory allInteractionsConcat = new bytes(cumulativeLength + config.customData.length);
        uint256 offset = 0;

        for (uint256 i = 0; i < allInteractions.length; i++) {
            bytes memory interaction = allInteractions[i];
            for (uint256 j = 0; j < interaction.length; j++) {
                allInteractionsConcat[offset + j] = interaction[j];
            }
            offset += interaction.length;
        }

        // Add custom data
        for (uint256 i = 0; i < config.customData.length; i++) {
            allInteractionsConcat[offset + i] = config.customData[i];
        }

        // Build extension
        extension = abi.encodePacked(uint256(offsets), allInteractionsConcat);

        hasExtension = true;
    }

    /**
     * @notice Builds a complete order from configuration
     * @param config The order configuration
     * @return order The built order
     */
    function buildOrder(OrderConfig memory config) internal pure returns (IOrderMixin.Order memory order) {
        // Build maker traits
        MakerTraits makerTraits = buildMakerTraits(config.makerTraits);

        // Build extension
        (bytes memory extension, bool hasExtension) = buildOrderExtension(config.extension);

        // Set extension flag if needed
        if (hasExtension) {
            uint256 traits = MakerTraits.unwrap(makerTraits);
            traits |= _HAS_EXTENSION_FLAG;
            makerTraits = MakerTraits.wrap(traits);
        }

        // Set interaction flags
        if (config.extension.preInteraction.length > 0) {
            uint256 traits = MakerTraits.unwrap(makerTraits);
            traits |= _NEED_PREINTERACTION_FLAG;
            makerTraits = MakerTraits.wrap(traits);
        }

        if (config.extension.postInteraction.length > 0) {
            uint256 traits = MakerTraits.unwrap(makerTraits);
            traits |= _NEED_POSTINTERACTION_FLAG;
            makerTraits = MakerTraits.wrap(traits);
        }

        // Calculate salt
        uint256 salt = 1;
        if (hasExtension) {
            salt = uint256(keccak256(extension)) & ((1 << 160) - 1);
        }

        // Build order
        order = IOrderMixin.Order({
            salt: salt,
            maker: Address.wrap(uint160(config.maker)),
            receiver: Address.wrap(uint160(config.receiver)),
            makerAsset: Address.wrap(uint160(config.makerAsset)),
            takerAsset: Address.wrap(uint160(config.takerAsset)),
            makingAmount: config.makingAmount,
            takingAmount: config.takingAmount,
            makerTraits: makerTraits
        });
    }

    /**
     * @notice Builds maker traits for RFQ orders (no multiple fills, no partial fills, no epoch check)
     * @param config The maker traits configuration
     * @return makerTraits The encoded maker traits for RFQ
     */
    function buildMakerTraitsRFQ(MakerTraitsConfig memory config) internal pure returns (MakerTraits) {
        // Override RFQ-specific settings
        config.allowMultipleFills = false;
        config.allowPartialFill = true;
        config.shouldCheckEpoch = false;

        return buildMakerTraits(config);
    }

    /**
     * @notice Builds order for RFQ (Request for Quote)
     * @param config The order configuration
     * @return order The built RFQ order
     */
    function buildOrderRFQ(OrderConfig memory config) internal pure returns (IOrderMixin.Order memory order) {
        // Build RFQ maker traits
        MakerTraits makerTraits = buildMakerTraitsRFQ(config.makerTraits);

        // Build extension
        (bytes memory extension, bool hasExtension) = buildOrderExtension(config.extension);

        // Set extension flag if needed
        if (hasExtension) {
            uint256 traits = MakerTraits.unwrap(makerTraits);
            traits |= _HAS_EXTENSION_FLAG;
            makerTraits = MakerTraits.wrap(traits);
        }

        // Calculate salt
        uint256 salt = 1;
        if (hasExtension) {
            salt = uint256(keccak256(extension)) & ((1 << 160) - 1);
        }

        // Build order
        order = IOrderMixin.Order({
            salt: salt,
            maker: Address.wrap(uint160(config.maker)),
            receiver: Address.wrap(uint160(config.receiver)),
            makerAsset: Address.wrap(uint160(config.makerAsset)),
            takerAsset: Address.wrap(uint160(config.takerAsset)),
            makingAmount: config.makingAmount,
            takingAmount: config.takingAmount,
            makerTraits: makerTraits
        });
    }

    /**
     * @notice Creates a simple order with basic configuration
     * @param maker The maker address
     * @param makerAsset The maker asset address
     * @param takerAsset The taker asset address
     * @param makingAmount The making amount
     * @param takingAmount The taking amount
     * @return order The built order
     */
    function createSimpleOrder(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount
    ) internal pure returns (IOrderMixin.Order memory order) {
        OrderConfig memory config = OrderConfig({
            maker: maker,
            receiver: address(0),
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: MakerTraitsConfig({
                allowedSender: address(0),
                shouldCheckEpoch: false,
                allowPartialFill: true,
                allowMultipleFills: true,
                usePermit2: false,
                unwrapWeth: false,
                expiry: 0,
                nonce: 0,
                series: 0
            }),
            extension: OrderExtensionConfig({
                makerAssetSuffix: "",
                takerAssetSuffix: "",
                makingAmountData: "",
                takingAmountData: "",
                predicate: "",
                permit: "",
                preInteraction: "",
                postInteraction: "",
                customData: ""
            })
        });

        return buildOrder(config);
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
    ) internal pure returns (IOrderMixin.Order memory order) {
        OrderConfig memory config = OrderConfig({
            maker: maker,
            receiver: address(0),
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: MakerTraitsConfig({
                allowedSender: address(0),
                shouldCheckEpoch: false,
                allowPartialFill: true,
                allowMultipleFills: true,
                usePermit2: false,
                unwrapWeth: false,
                expiry: 0,
                nonce: 0,
                series: 0
            }),
            extension: OrderExtensionConfig({
                makerAssetSuffix: "",
                takerAssetSuffix: "",
                makingAmountData: "",
                takingAmountData: "",
                predicate: "",
                permit: "",
                preInteraction: abi.encodePacked(preInteraction),
                postInteraction: abi.encodePacked(postInteraction),
                customData: ""
            })
        });

        return buildOrder(config);
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
    ) internal pure returns (IOrderMixin.Order memory order) {
        OrderConfig memory config = OrderConfig({
            maker: maker,
            receiver: address(0),
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            makerTraits: MakerTraitsConfig({
                allowedSender: address(0),
                shouldCheckEpoch: false,
                allowPartialFill: true,
                allowMultipleFills: true,
                usePermit2: false,
                unwrapWeth: false,
                expiry: 0,
                nonce: 0,
                series: 0
            }),
            extension: OrderExtensionConfig({
                makerAssetSuffix: "",
                takerAssetSuffix: "",
                makingAmountData: abi.encodePacked(amountGetter),
                takingAmountData: abi.encodePacked(amountGetter),
                predicate: "",
                permit: "",
                preInteraction: "",
                postInteraction: "",
                customData: ""
            })
        });

        return buildOrder(config);
    }
}
