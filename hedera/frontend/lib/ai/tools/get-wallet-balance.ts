import { tool } from "ai";
import { z } from "zod";
import { getWalletBalances, getPortfolioSummary } from "./get-wallet-balances";
import { serializeBigInt } from "@/lib/utils";

export const getWalletBalance = tool({
  description:
    "Get wallet balances for popular tokens only (HBAR, USDC, USDT, etc.) from Hedera Testnet by default, or optionally from multiple blockchain networks. Use this for general wallet balance checks of popular tokens, NOT for tokens the user has deployed themselves.",
  inputSchema: z.object({
    address: z
      .string()
      .describe(
        "The wallet address to check balances for (must be a valid Ethereum address format)"
      ),
    chainIds: z
      .array(z.number())
      .optional()
      .describe(
        "Array of chain IDs to check balances on. If not provided, defaults to Hedera Testnet only (296)"
      ),
    hederaOnly: z
      .boolean()
      .optional()
      .describe(
        "If true, only fetch balances from Hedera Testnet (296). Defaults to true."
      ),
  }),
  execute: async ({ address, chainIds, hederaOnly }) => {
    try {
      const balances = await getWalletBalances({
        walletAddress: address,
        chainIds,
        hederaOnly,
      });

      const portfolioSummary = getPortfolioSummary(balances);

      const result = {
        success: true,
        walletAddress: address,
        portfolioSummary,
        balances: balances.map((chainBalance) => ({
          chainId: chainBalance.chainId,
          chainName: chainBalance.chainName,
          address: chainBalance.address,
          balances: chainBalance.balances.map((tokenBalance) => ({
            symbol: tokenBalance.symbol,
            name: tokenBalance.name,
            balance: tokenBalance.formattedBalance,
            address: tokenBalance.address,
            isNative: tokenBalance.isNative,
          })),
        })),
        timestamp: new Date().toISOString(),
      };

      // Serialize any BigInt values to prevent JSON serialization errors
      console.log(result);
      debugger;
      return serializeBigInt(result);
    } catch (error: any) {
      console.error("Error fetching wallet balances:", error);
      return {
        success: false,
        error: error.message || "Failed to fetch wallet balances",
        walletAddress: address,
        timestamp: new Date().toISOString(),
      };
    }
  },
});
