/**
 * Wallet Balance Tool for AI Chatbot
 *
 * This tool allows the AI to fetch wallet balances across supported chains
 */

import { createPublicClient, http, formatUnits } from "viem";
import { CHAINS, POPULAR_TOKENS, getChainConfig } from "@/lib/constants";

export interface WalletBalance {
  chainId: number;
  chainName: string;
  address: string;
  balances: TokenBalance[];
}

export interface TokenBalance {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  balance: string;
  formattedBalance: string;
  isNative: boolean;
}

export interface GetWalletBalancesParams {
  walletAddress: string;
  chainIds?: number[];
  hederaOnly?: boolean; // Flag to only fetch Hedera Testnet balances
}

/**
 * Get wallet balances for a specific chain
 */
async function getBalancesForChain(
  walletAddress: string,
  chainId: number
): Promise<WalletBalance> {
  try {
    const chainConfig = getChainConfig(chainId);
    if (!chainConfig) {
      console.error(`Chain with ID ${chainId} not supported`);
      return {
        chainId,
        chainName: `Unsupported Chain ${chainId}`,
        address: walletAddress,
        balances: [],
      };
    }

    // Create public client for the chain
    const publicClient = createPublicClient({
      transport: http(chainConfig.rpcUrls.default[0]),
      chain: {
        id: chainConfig.id,
        name: chainConfig.name,
        network: chainConfig.network,
        nativeCurrency: chainConfig.nativeCurrency,
        rpcUrls: {
          default: { http: chainConfig.rpcUrls.default },
          public: { http: chainConfig.rpcUrls.public },
        },
      },
    });

    const balances: TokenBalance[] = [];
    const tokens = POPULAR_TOKENS[chainId.toString()] || [];

    // Get native token balance
    try {
      const nativeBalance = await publicClient.getBalance({
        address: walletAddress as `0x${string}`,
      });

      balances.push({
        address: "0x0000000000000000000000000000000000000000",
        symbol: chainConfig.nativeCurrency.symbol,
        name: chainConfig.nativeCurrency.name,
        decimals: chainConfig.nativeCurrency.decimals,
        balance: nativeBalance.toString(),
        formattedBalance: (() => {
          try {
            return (
              formatUnits(nativeBalance, chainConfig.nativeCurrency.decimals) ||
              "0"
            );
          } catch (error) {
            console.error(
              `Failed to format native balance for chain ${chainId}:`,
              error
            );
            return "0";
          }
        })(),
        isNative: true,
      });
    } catch (error) {
      console.error(
        `Failed to get native balance for chain ${chainId}:`,
        error
      );
      // Add default zero balance for native token when read fails
      balances.push({
        address: "0x0000000000000000000000000000000000000000",
        symbol: chainConfig.nativeCurrency.symbol,
        name: chainConfig.nativeCurrency.name,
        decimals: chainConfig.nativeCurrency.decimals,
        balance: "0",
        formattedBalance: "0",
        isNative: true,
      });
    }

    // Get ERC-20 token balances
    for (const token of tokens) {
      if (token.address === "0x0000000000000000000000000000000000000000") {
        continue; // Skip native token as we already handled it
      }

      try {
        // Create contract instance for ERC-20 token
        const contract = {
          address: token.address as `0x${string}`,
          abi: [
            {
              type: "function",
              name: "balanceOf",
              inputs: [{ name: "account", type: "address" }],
              outputs: [{ name: "", type: "uint256" }],
              stateMutability: "view",
            },
          ],
        };

        const balance = (await publicClient.readContract({
          ...contract,
          functionName: "balanceOf",
          args: [walletAddress as `0x${string}`],
        })) as bigint;

        // Convert BigInt to string to avoid serialization issues
        const balanceString = balance.toString();
        const formattedBalance = (() => {
          try {
            return formatUnits(balance, token.decimals) || "0";
          } catch (error) {
            console.error(
              `Failed to format balance for token ${token.symbol}:`,
              error
            );
            return "0";
          }
        })();

        balances.push({
          address: token.address,
          symbol: token.symbol,
          name: token.name,
          decimals: token.decimals,
          balance: balanceString,
          formattedBalance: formattedBalance,
          isNative: false,
        });
      } catch (error) {
        console.error(
          `Failed to get balance for token ${token.symbol} on chain ${chainId}:`,
          error
        );
        // Add token with zero balance if we can't fetch it
        balances.push({
          address: token.address,
          symbol: token.symbol,
          name: token.name,
          decimals: token.decimals,
          balance: "0",
          formattedBalance: "0",
          isNative: false,
        });
      }
    }

    return {
      chainId,
      chainName: chainConfig.name,
      address: walletAddress,
      balances,
    };
  } catch (error) {
    console.error(`Failed to get balances for chain ${chainId}:`, error);
    // Return empty balance result when any read call fails
    return {
      chainId,
      chainName: `Chain ${chainId}`,
      address: walletAddress,
      balances: [],
    };
  }
}

/**
 * Get wallet balances across multiple chains
 */
export async function getWalletBalances({
  walletAddress,
  chainIds,
  hederaOnly = true, // Default to Hedera Testnet only
}: GetWalletBalancesParams): Promise<WalletBalance[]> {
  try {
    if (!walletAddress || !walletAddress.match(/^0x[a-fA-F0-9]{40}$/)) {
      console.error("Invalid wallet address format:", walletAddress);
      return [];
    }

    // Determine which chains to fetch balances for
    const targetChainIds =
      chainIds || (hederaOnly ? [296] : [296, 11155111, 84532]);

    const results: WalletBalance[] = [];

    // Fetch balances for each chain in parallel
    const promises = targetChainIds.map((chainId) =>
      getBalancesForChain(walletAddress, chainId).catch((error) => {
        console.error(`Failed to get balances for chain ${chainId}:`, error);
        return {
          chainId,
          chainName: `Chain ${chainId}`,
          address: walletAddress,
          balances: [],
        };
      })
    );

    const chainResults = await Promise.all(promises);
    results.push(...chainResults);

    return results;
  } catch (error) {
    console.error("Failed to get wallet balances:", error);
    // Return empty results when any read call fails
    return [];
  }
}

/**
 * Get total portfolio value (simplified - just counts non-zero balances)
 */
export function getPortfolioSummary(balances: WalletBalance[]): {
  totalChains: number;
  totalTokens: number;
  chainsWithBalances: number;
  summary: string;
} {
  try {
    const totalChains = balances?.length || 0;
    let totalTokens = 0;
    let chainsWithBalances = 0;

    balances?.forEach((chainBalance) => {
      try {
        const nonZeroBalances =
          chainBalance.balances?.filter(
            (balance) =>
              balance.balance !== "0" &&
              Number.parseFloat(balance.formattedBalance || "0") > 0
          ) || [];

        if (nonZeroBalances.length > 0) {
          chainsWithBalances++;
        }

        totalTokens += nonZeroBalances.length;
      } catch (error) {
        console.error("Error processing chain balance:", error);
        // Continue with other chains
      }
    });

    const summary = `Portfolio Summary: ${chainsWithBalances}/${totalChains} chains have balances, ${totalTokens} tokens with non-zero balances`;

    return {
      totalChains,
      totalTokens,
      chainsWithBalances,
      summary,
    };
  } catch (error) {
    console.error("Error generating portfolio summary:", error);
    // Return default summary when any read call fails
    return {
      totalChains: 0,
      totalTokens: 0,
      chainsWithBalances: 0,
      summary: "Portfolio Summary: Unable to load balance data",
    };
  }
}
