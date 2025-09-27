'use client';
import { toast } from '@/components/toast';
import { Button } from '@/components/ui/button';
import { clearUserSession } from '@/lib/auth/session-actions';
import {
  clearWalletAddress,
  setAuthenticated,
  setWalletAddress,
} from '@/lib/store/features/userAccountDetailsSlice';
import { useAppDispatch, useAppSelector } from '@/lib/store/hooks';
import { CopyIcon } from 'lucide-react';
import { signIn, signOut, useSession } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { useAccount, useDisconnect, useSignMessage } from 'wagmi';

export default function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();
  const { signMessageAsync } = useSignMessage();
  const { data: session, status: sessionStatus } = useSession();
  const dispatch = useAppDispatch();
  const router = useRouter();
  const isAuthenticated = useAppSelector(
    (state) => (state.userAccountDetails as any).isAuthenticated,
  );
  const [isSigning, setIsSigning] = useState(false);

  // Sync Redux state with NextAuth session on mount and session changes
  useEffect(() => {
    if (sessionStatus === 'loading') return; // Wait for session to load

    if (session?.user?.type === 'wallet' && session.user.walletAddress) {
      // User is authenticated via wallet, sync Redux state
      dispatch(setWalletAddress(session.user.walletAddress));
      dispatch(setAuthenticated(true));
    } else if (sessionStatus === 'unauthenticated' || !session) {
      // No session, clear Redux state
      dispatch(clearWalletAddress());
      dispatch(setAuthenticated(false));
    }
  }, [session, sessionStatus, dispatch]);

  // Update Redux store when wallet connects/disconnects
  useEffect(() => {
    if (isConnected && address) {
      dispatch(setWalletAddress(address));
    } else if (!isConnected) {
      dispatch(clearWalletAddress());
      dispatch(setAuthenticated(false));
    }
  }, [isConnected, address, dispatch]);

  // Auto-trigger sign message when wallet connects (only if not already authenticated)
  useEffect(() => {
    if (
      isConnected &&
      address &&
      !isAuthenticated &&
      !isSigning &&
      sessionStatus !== 'loading' &&
      session?.user?.type !== 'wallet'
    ) {
      handleWalletSignIn();
    }
  }, [
    isConnected,
    address,
    isAuthenticated,
    isSigning,
    sessionStatus,
    session,
  ]);

  const handleWalletSignIn = async () => {
    if (!isConnected || !address) {
      return;
    }

    setIsSigning(true);
    try {
      // Generate a unique nonce and message using deterministic approach
      const nonce = address.slice(2, 15); // Use wallet address as base for nonce
      const timestamp = Date.now();
      const message = `Sign this message to authenticate with HederaAI Chatbot.\n\nWallet: ${address}\nNonce: ${nonce}\nTimestamp: ${timestamp}`;

      // Request signature from user
      const signature = await signMessageAsync({
        message,
      });

      // Send to server for verification
      const response = await fetch('/api/auth/wallet', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          address,
          signature,
          message,
        }),
      });

      if (!response.ok) {
        throw new Error('Authentication failed');
      }

      const result = await response.json();

      if (result.success) {
        // Sign in with NextAuth
        await signIn('wallet', {
          address,
          signature,
          message,
          redirect: false,
        });

        toast({
          type: 'success',
          description: 'Successfully authenticated with wallet!',
        });

        dispatch(setAuthenticated(true));
      } else {
        throw new Error(result.error || 'Authentication failed');
      }
    } catch (error: any) {
      // Check if user rejected the signature request
      if (
        error?.cause?.code === 4001 ||
        error?.code === 4001 ||
        error?.message?.includes('User rejected') ||
        error?.message?.includes('not been authorized')
      ) {
        console.log('User rejected signature request');
        // Don't show error toast for user rejection
        disconnect();
        return;
      }
      const errorMessage =
        error instanceof Error ? error.message : 'Sign in failed';
      toast({
        type: 'error',
        description: errorMessage,
      });
    } finally {
      setIsSigning(false);
    }
  };

  if (isConnected) {
    const handleCopyAddress = () => {
      if (address) {
        navigator.clipboard.writeText(address);
        toast({
          type: 'success',
          description: 'Address copied to clipboard!',
        });
      }
    };

    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground">
          {address?.slice(0, 6)}...{address?.slice(-4)}
        </span>
        <Button variant="ghost" size="icon" onClick={handleCopyAddress}>
          <CopyIcon className="size-4" />
        </Button>
        {isSigning ? (
          <span className="text-xs text-muted-foreground">Signing...</span>
        ) : isAuthenticated ? (
          <span className="text-xs text-green-600">✓ Authenticated</span>
        ) : (
          <Button
            variant="outline"
            size="sm"
            onClick={handleWalletSignIn}
            disabled={isSigning}
          >
            {isSigning ? 'Signing...' : 'Sign Message'}
          </Button>
        )}
        <Button
          variant="outline"
          size="sm"
          onClick={async () => {
            try {
              // Disconnect wallet
              disconnect();
              // Clear wallet address and authentication state from Redux
              dispatch(clearWalletAddress());
              dispatch(setAuthenticated(false));
              // Sign out from NextAuth session without redirect
              await signOut({ redirect: false });
              // Clear server-side session and revalidate paths
              await clearUserSession();
              // Navigate without full page reload
              router.replace('/');
            } catch (error) {
              console.error('Error during disconnect:', error);
              // Still try to clear local state even if signOut fails
              dispatch(clearWalletAddress());
              dispatch(setAuthenticated(false));
              // Fallback to manual redirect
              router.replace('/');
            }
          }}
        >
          Disconnect
        </Button>
      </div>
    );
  }

  return <appkit-button />;
}
