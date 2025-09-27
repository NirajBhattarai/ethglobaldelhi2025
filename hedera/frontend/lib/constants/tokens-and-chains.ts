/**
 * Popular Tokens and Blockchain Networks Constants
 *
 * This file contains configurations for popular tokens and different blockchain networks
 * that can be used throughout the application for token swaps, deployments, and interactions.
 */

// Chain configurations
export interface ChainConfig {
  id: number;
  name: string;
  network: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  rpcUrls: {
    default: string[];
    public: string[];
  };
  blockExplorerUrls: string[];
  testnet: boolean;
}

// Token configuration
export interface TokenConfig {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  logoURI?: string;
  chainId: number;
}

// Popular blockchain networks
export const CHAINS: Record<string, ChainConfig> = {
  // Hedera Networks
  "hedera-testnet": {
    id: 296,
    name: "Hedera Testnet",
    network: "hedera-testnet",
    nativeCurrency: {
      name: "HBAR",
      symbol: "HBAR",
      decimals: 18,
    },
    rpcUrls: {
      default: ["https://testnet.hashio.io/api/v1"],
      public: ["https://testnet.hashio.io/api/v1"],
    },
    blockExplorerUrls: ["https://hashscan.io/testnet"],
    testnet: true,
  },

  // Ethereum Networks
  "ethereum-sepolia": {
    id: 11155111,
    name: "Sepolia",
    network: "sepolia",
    nativeCurrency: {
      name: "Sepolia Ether",
      symbol: "ETH",
      decimals: 18,
    },
    rpcUrls: {
      default: ["https://sepolia.infura.io/v3/demo"],
      public: ["https://sepolia.infura.io/v3/demo"],
    },
    blockExplorerUrls: ["https://sepolia.etherscan.io"],
    testnet: true,
  },

  // Base Networks
  "base-sepolia": {
    id: 84532,
    name: "Base Sepolia",
    network: "base-sepolia",
    nativeCurrency: {
      name: "Ether",
      symbol: "ETH",
      decimals: 18,
    },
    rpcUrls: {
      default: ["https://sepolia.base.org"],
      public: ["https://sepolia.base.org"],
    },
    blockExplorerUrls: ["https://sepolia.basescan.org"],
    testnet: true,
  },
};

// Popular tokens by chain
export const POPULAR_TOKENS: Record<string, TokenConfig[]> = {
  // Hedera Testnet tokens
  "296": [
    {
      address: "0x0000000000000000000000000000000000000000",
      symbol: "HBAR",
      name: "Hedera Hashgraph",
      decimals: 18,
      chainId: 296,
    },
    {
      address: "0xb9be1183c5c05b55dd2ff9a316d93d92a784d9cb",
      symbol: "USDC",
      name: "USD Coin",
      decimals: 18,
      chainId: 296,
    },
    {
      address: "0x7169D38820dfd117C3FA1f22a697dBA58d90BA06",
      symbol: "USDT",
      name: "Tether USD",
      decimals: 18,
      chainId: 296,
    },
    {
      address: "0x0000000000000000000000000000000000000000",
      symbol: "WETH",
      name: "Wrapped Ether",
      decimals: 18,
      chainId: 296,
    },
    // Add more Hedera testnet tokens as they become available
  ],

  // Ethereum Sepolia testnet tokens
  "11155111": [
    {
      address: "0x0000000000000000000000000000000000000000",
      symbol: "ETH",
      name: "Ethereum",
      decimals: 18,
      chainId: 11155111,
    },
    {
      address: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
      symbol: "LINK",
      name: "ChainLink Token",
      decimals: 18,
      chainId: 11155111,
    },
    {
      address: "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8",
      symbol: "USDC",
      name: "USD Coin",
      decimals: 6,
      chainId: 11155111,
    },
    {
      address: "0x7169D38820dfd117C3FA1f22a697dBA58d90BA06",
      symbol: "USDT",
      name: "Tether USD",
      decimals: 6,
      chainId: 11155111,
    },
  ],

  // Base Sepolia testnet tokens
  "84532": [
    {
      address: "0x0000000000000000000000000000000000000000",
      symbol: "ETH",
      name: "Ethereum",
      decimals: 18,
      chainId: 84532,
    },
    {
      address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      symbol: "USDC",
      name: "USD Coin",
      decimals: 6,
      chainId: 84532,
    },
    {
      address: "0x4200000000000000000000000000000000000006",
      symbol: "WETH",
      name: "Wrapped Ether",
      decimals: 18,
      chainId: 84532,
    },
  ],
};

// Helper functions
export const getChainConfig = (chainId: number): ChainConfig | undefined => {
  return Object.values(CHAINS).find((chain) => chain.id === chainId);
};

export const getChainConfigByName = (
  networkName: string
): ChainConfig | undefined => {
  return CHAINS[networkName];
};

export const getPopularTokens = (chainId: number): TokenConfig[] => {
  return POPULAR_TOKENS[chainId.toString()] || [];
};

export const getTokenByAddress = (
  chainId: number,
  address: string
): TokenConfig | undefined => {
  const tokens = getPopularTokens(chainId);
  return tokens.find(
    (token) => token.address.toLowerCase() === address.toLowerCase()
  );
};

export const getNativeToken = (chainId: number): TokenConfig | undefined => {
  const chain = getChainConfig(chainId);
  if (!chain) return undefined;

  return {
    address: "0x0000000000000000000000000000000000000000",
    symbol: chain.nativeCurrency.symbol,
    name: chain.nativeCurrency.name,
    decimals: chain.nativeCurrency.decimals,
    chainId: chain.id,
  };
};

// Default chain for the application
export const DEFAULT_CHAIN = "hedera-testnet";

// Supported chains for token deployment
export const SUPPORTED_DEPLOYMENT_CHAINS = [
  "hedera-testnet",
  "ethereum-sepolia",
  "base-sepolia",
];

// Chain IDs for quick reference
export const CHAIN_IDS = {
  HEDERA_TESTNET: 296,
  ETHEREUM_SEPOLIA: 11155111,
  BASE_SEPOLIA: 84532,
} as const;

// Token symbols for quick reference
export const TOKEN_SYMBOLS = {
  HBAR: "HBAR",
  ETH: "ETH",
  USDC: "USDC",
  USDT: "USDT",
  LINK: "LINK",
  WETH: "WETH",
} as const;
