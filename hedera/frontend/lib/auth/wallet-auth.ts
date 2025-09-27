import { verifyMessage } from 'viem';

export interface WalletAuthData {
  address: string;
  signature: string;
  message: string;
}

export interface WalletUser {
  id: string;
  walletAddress: string;
  type: 'wallet';
}

/**
 * Generates a nonce message for wallet authentication
 */
export function generateAuthMessage(address: string, nonce: string): string {
  return `Sign this message to authenticate with HederaAI Chatbot.\n\nWallet: ${address}\nNonce: ${nonce}\nTimestamp: ${Date.now()}`;
}

/**
 * Verifies a wallet signature against the provided message and address
 */
export async function verifyWalletSignature(
  address: string,
  signature: string,
  message: string,
): Promise<boolean> {
  try {
    const isValid = await verifyMessage({
      address: address as `0x${string}`,
      message,
      signature: signature as `0x${string}`,
    });
    return isValid;
  } catch (error) {
    console.error('Signature verification failed:', error);
    return false;
  }
}

/**
 * Authenticates a user using wallet signature
 * This function should only be called from server-side code
 */
export async function authenticateWalletUser(
  walletData: WalletAuthData,
): Promise<WalletUser | null> {
  try {
    // Verify the signature
    const isValidSignature = await verifyWalletSignature(
      walletData.address,
      walletData.signature,
      walletData.message,
    );

    if (!isValidSignature) {
      return null;
    }

    // Import database functions dynamically to avoid server-only issues
    const { createWalletUser, getUserByWalletAddress } = await import(
      '@/lib/db/queries'
    );

    // Check if user exists
    const existingUsers = await getUserByWalletAddress(walletData.address);

    if (existingUsers.length > 0) {
      const [user] = existingUsers;
      return {
        id: user.id,
        walletAddress: user.walletAddress || '',
        type: 'wallet',
      };
    }

    // Create new user if doesn't exist
    const [newUser] = await createWalletUser(walletData.address);
    return {
      id: newUser.id,
      walletAddress: newUser.walletAddress || '',
      type: 'wallet',
    };
  } catch (error) {
    console.error('Wallet authentication failed:', error);
    return null;
  }
}