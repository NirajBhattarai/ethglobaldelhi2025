"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Wallet,
  Coins,
  TrendingUp,
  ExternalLink,
  Copy,
  CheckCircle,
  AlertCircle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "@/components/toast";

interface TokenBalance {
  symbol: string;
  name: string;
  balance: string;
  address: string;
  isNative: boolean;
}

interface ChainBalance {
  chainId: number;
  chainName: string;
  address: string;
  balances: TokenBalance[];
}

interface WalletBalanceDisplayProps {
  walletAddress: string;
  balances: ChainBalance[];
  portfolioSummary?: {
    totalChains: number;
    totalTokens: number;
    chainsWithBalances: number;
    summary: string;
  };
  isLoading?: boolean;
  error?: string;
}

export function WalletBalanceDisplay({
  walletAddress,
  balances,
  portfolioSummary,
  isLoading = false,
  error,
}: WalletBalanceDisplayProps) {
  const copyToClipboard = (text: string, label: string) => {
    navigator.clipboard.writeText(text);
    toast({
      type: "success",
      description: `${label} copied to clipboard`,
    });
  };

  const formatBalance = (balance: string): string => {
    // Handle undefined, null, or empty balance
    if (!balance || balance === "undefined" || balance === "null") {
      return "0";
    }

    const num = Number.parseFloat(balance);

    // Handle NaN or invalid numbers
    if (Number.isNaN(num)) {
      return "0";
    }

    if (num === 0) return "0";
    if (num < 0.000001) return "< 0.000001";
    if (num < 1) return num.toFixed(6);
    if (num < 1000) return num.toFixed(4);
    return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
  };

  const getChainIcon = (chainId: number): string => {
    switch (chainId) {
      case 296:
        return "🟢"; // Hedera
      case 11155111:
        return "🔷"; // Ethereum Sepolia
      case 84532:
        return "🔵"; // Base Sepolia
      default:
        return "⛓️";
    }
  };

  const getExplorerUrl = (chainId: number, address: string): string => {
    switch (chainId) {
      case 296:
        return `https://hashscan.io/testnet/account/${address}`;
      case 11155111:
        return `https://sepolia.etherscan.io/address/${address}`;
      case 84532:
        return `https://sepolia.basescan.org/address/${address}`;
      default:
        return "#";
    }
  };

  if (isLoading) {
    return (
      <Card className="w-full">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Wallet className="h-5 w-5 animate-pulse" />
            Loading Wallet Balances...
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="animate-pulse">
              <div className="h-4 bg-muted rounded w-3/4 mb-2" />
              <div className="h-3 bg-muted rounded w-1/2" />
            </div>
            <div className="animate-pulse">
              <div className="h-4 bg-muted rounded w-2/3 mb-2" />
              <div className="h-3 bg-muted rounded w-1/3" />
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="w-full border-red-200">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-red-600">
            <AlertCircle className="h-5 w-5" />
            Error Loading Balances
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-red-600 mb-4">{error}</p>
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <span>Wallet:</span>
            <code className="bg-muted px-2 py-1 rounded text-xs">
              {walletAddress.slice(0, 6)}...{walletAddress.slice(-4)}
            </code>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* Portfolio Summary */}
      {portfolioSummary && (
        <Card className="w-full">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <TrendingUp className="h-5 w-5" />
              Portfolio Overview
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
              <div className="text-center p-3 bg-blue-50 rounded-lg">
                <div className="text-2xl font-bold text-blue-600">
                  {portfolioSummary.chainsWithBalances}
                </div>
                <div className="text-sm text-muted-foreground">
                  Active Chains
                </div>
              </div>
              <div className="text-center p-3 bg-green-50 rounded-lg">
                <div className="text-2xl font-bold text-green-600">
                  {portfolioSummary.totalTokens}
                </div>
                <div className="text-sm text-muted-foreground">Tokens Held</div>
              </div>
              <div className="text-center p-3 bg-purple-50 rounded-lg">
                <div className="text-2xl font-bold text-purple-600">
                  {portfolioSummary.totalChains}
                </div>
                <div className="text-sm text-muted-foreground">
                  Total Chains
                </div>
              </div>
              <div className="text-center p-3 bg-orange-50 rounded-lg">
                <div className="text-2xl font-bold text-orange-600">
                  {balances.reduce(
                    (total, chain) => total + chain.balances.length,
                    0
                  )}
                </div>
                <div className="text-sm text-muted-foreground">
                  Total Assets
                </div>
              </div>
            </div>
            <div className="text-center p-3 bg-gray-50 rounded-lg">
              <p className="text-sm text-muted-foreground">
                {portfolioSummary.summary}
              </p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Wallet Address */}
      <Card className="w-full">
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Wallet className="h-5 w-5" />
            Wallet Address
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-2">
            <code className="text-sm bg-muted px-3 py-2 rounded flex-1 font-mono">
              {walletAddress}
            </code>
            <Button
              variant="outline"
              size="sm"
              onClick={() => copyToClipboard(walletAddress, "Wallet address")}
            >
              <Copy className="h-4 w-4" />
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Combined Balance Table */}
      <Card className="w-full">
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Coins className="h-5 w-5" />
              Wallet Balance Summary
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                const summary = balances
                  .map(
                    (chain) =>
                      `${chain.chainName}: ${
                        chain.balances
                          .filter((b) => Number.parseFloat(b.balance) > 0)
                          .map((b) => `${formatBalance(b.balance)} ${b.symbol}`)
                          .join(", ") || "No balances"
                      }`
                  )
                  .join("\n");
                copyToClipboard(summary, "Balance summary");
              }}
            >
              <Copy className="h-4 w-4 mr-1" />
              Copy Summary
            </Button>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="border-b">
                  <th className="text-left py-3 px-4 font-medium text-muted-foreground">
                    Chain
                  </th>
                  <th className="text-left py-3 px-4 font-medium text-muted-foreground">
                    Token
                  </th>
                  <th className="text-left py-3 px-4 font-medium text-muted-foreground">
                    Type
                  </th>
                  <th className="text-right py-3 px-4 font-medium text-muted-foreground">
                    Balance
                  </th>
                  <th className="text-center py-3 px-4 font-medium text-muted-foreground">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody>
                {balances.map((chainBalance) => {
                  const nonZeroBalances = chainBalance.balances.filter(
                    (balance) => Number.parseFloat(balance.balance) > 0
                  );

                  if (nonZeroBalances.length === 0) {
                    return (
                      <tr key={chainBalance.chainId} className="border-b">
                        <td className="py-4 px-4">
                          <div className="flex items-center gap-2">
                            <span className="text-lg">
                              {getChainIcon(chainBalance.chainId)}
                            </span>
                            <div>
                              <div className="font-medium">
                                {chainBalance.chainName}
                              </div>
                              <div className="text-xs text-muted-foreground">
                                ID: {chainBalance.chainId}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td className="py-4 px-4 text-muted-foreground">
                          No tokens
                        </td>
                        <td className="py-4 px-4 text-muted-foreground">-</td>
                        <td className="py-4 px-4 text-right text-muted-foreground">
                          0
                        </td>
                        <td className="py-4 px-4 text-center">
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() =>
                              window.open(
                                getExplorerUrl(
                                  chainBalance.chainId,
                                  chainBalance.address
                                ),
                                "_blank"
                              )
                            }
                          >
                            <ExternalLink className="h-4 w-4" />
                          </Button>
                        </td>
                      </tr>
                    );
                  }

                  return nonZeroBalances.map((tokenBalance, index) => (
                    <tr
                      key={`${chainBalance.chainId}-${tokenBalance.address}-${index}`}
                      className="border-b"
                    >
                      <td className="py-4 px-4">
                        {index === 0 && (
                          <div className="flex items-center gap-2">
                            <span className="text-lg">
                              {getChainIcon(chainBalance.chainId)}
                            </span>
                            <div>
                              <div className="font-medium">
                                {chainBalance.chainName}
                              </div>
                              <div className="text-xs text-muted-foreground">
                                ID: {chainBalance.chainId}
                              </div>
                            </div>
                          </div>
                        )}
                      </td>
                      <td className="py-4 px-4">
                        <div className="flex items-center gap-2">
                          <Coins className="h-4 w-4 text-muted-foreground" />
                          <div>
                            <div className="font-medium">
                              {tokenBalance.symbol}
                            </div>
                            <div className="text-xs text-muted-foreground">
                              {tokenBalance.name}
                            </div>
                          </div>
                        </div>
                      </td>
                      <td className="py-4 px-4">
                        {tokenBalance.isNative ? (
                          <Badge variant="default" className="text-xs">
                            Native
                          </Badge>
                        ) : (
                          <Badge variant="secondary" className="text-xs">
                            ERC-20
                          </Badge>
                        )}
                      </td>
                      <td className="py-4 px-4 text-right">
                        <div className="font-semibold">
                          {formatBalance(tokenBalance.balance)}
                        </div>
                        <div className="text-xs text-muted-foreground">
                          {tokenBalance.symbol}
                        </div>
                      </td>
                      <td className="py-4 px-4 text-center">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() =>
                            window.open(
                              getExplorerUrl(
                                chainBalance.chainId,
                                chainBalance.address
                              ),
                              "_blank"
                            )
                          }
                        >
                          <ExternalLink className="h-4 w-4" />
                        </Button>
                      </td>
                    </tr>
                  ));
                })}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {/* Success Message */}
      <Card className="w-full border-green-200 bg-green-50">
        <CardContent className="pt-6">
          <div className="flex items-center gap-2 text-green-700">
            <CheckCircle className="h-5 w-5" />
            <span className="font-medium">Balances Updated Successfully</span>
          </div>
          <p className="text-sm text-green-600 mt-1">
            Wallet balances have been fetched across all supported chains
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
