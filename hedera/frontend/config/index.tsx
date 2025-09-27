import { WagmiAdapter } from '@reown/appkit-adapter-wagmi';
import { hederaTestnet, polygonAmoy } from '@reown/appkit/networks';
import { defineChain } from 'viem';

// Get projectId from https://dashboard.reown.com
export const projectId = process.env.NEXT_PUBLIC_PROJECT_ID;

if (!projectId) {
  throw new Error('Project ID is not defined');
}

// Create a custom Hedera Testnet configuration with better RPC handling
const customHederaTestnet = defineChain({
  id: 296,
  name: 'Hedera Testnet',
  network: 'hedera-testnet',
  nativeCurrency: {
    decimals: 18,
    name: 'HBAR',
    symbol: 'HBAR',
  },
  rpcUrls: {
    default: {
      http: [
        'https://testnet.hashio.io/api/v1',
        'https://testnet.hashio.io/api/v1/relay',
        'https://testnet.hashio.io/api/v1/relay/hedera',
      ],
    },
    public: {
      http: [
        'https://testnet.hashio.io/api/v1',
        'https://testnet.hashio.io/api/v1/relay',
        'https://testnet.hashio.io/api/v1/relay/hedera',
      ],
    },
  },
  blockExplorers: {
    default: {
      name: 'HashScan',
      url: 'https://hashscan.io/testnet',
    },
  },
  testnet: true,
});

export const networks = [customHederaTestnet, polygonAmoy];

// Set up the Wagmi Adapter (Config)
export const wagmiAdapter = new WagmiAdapter({
  projectId,
  networks,
});

export const config = wagmiAdapter.wagmiConfig;
