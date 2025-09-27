'use client';

import { toast } from '@/components/toast';
import { Button } from '@/components/ui/button';
import {
  clearWalletAddress,
  setWalletAddress,
} from '@/lib/store/features/userAccountDetailsSlice';
import { useAppDispatch } from '@/lib/store/hooks';
import { signIn } from 'next-auth/react';
import { useEffect, useState } from 'react';
import { useAccount, useDisconnect, useSignMessage } from 'wagmi';

export default function ConnectButton() {
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();
  const { signMessageAsync } = useSignMessage();
  const [isSigning, setIsSigning] = useState(false);
  const [hasSigned, setHasSigned] = useState(false);
  const dispatch = useAppDispatch();
  
  // Update Redux store when wallet connects/disconnects
  useEffect(() => {
    if (isConnected && address) {
      dispatch(setWalletAddress(address));
    } else {
      dispatch(clearWalletAddress());
    }
  }, [isConnected, address, dispatch]);

  // Auto-trigger sign message when wallet connects
  useEffect(() => {
    if (isConnected && address && !hasSigned && !isSigning) {
      handleWalletSignIn();
    }
  }, [isConnected, address, hasSigned, isSigning]);

  const handleWalletSignIn = async () => {
    if (!isConnected || !address) {
      return;
    }

    setIsSigning(true);

    try {
      // Generate a unique nonce and message
      const nonce = Math.random().toString(36).substring(2, 15);
      const message = `Sign this message to authenticate with HederaAI Chatbot.\n\nWallet: ${address}\nNonce: ${nonce}\nTimestamp: ${Date.now()}`;

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

        setHasSigned(true);
      } else {
        throw new Error(result.error || 'Authentication failed');
      }
    }catch (error: any) {
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
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground">
          {address?.slice(0, 6)}...{address?.slice(-4)}
        </span>
        {isSigning ? (
          <span className="text-xs text-muted-foreground">Signing...</span>
        ) : hasSigned ? (
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
          onClick={() => {
            setHasSigned(false);
            disconnect();
             dispatch(clearWalletAddress());
          }}
        >
          Disconnect
        </Button>
      </div>
    );
  }

  return <appkit-button />;
}