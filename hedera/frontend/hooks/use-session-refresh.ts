import { useSession } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

/**
 * Custom hook to handle session refresh and navigation
 * This helps avoid full page reloads while ensuring session state is properly updated
 */
export function useSessionRefresh() {
  const { data: session, status, update } = useSession();
  const router = useRouter();

  const refreshSession = async () => {
    try {
      // Force session update
      await update();
      // Use router.refresh() to update server components without full page reload
      router.refresh();
    } catch (error) {
      console.error('Error refreshing session:', error);
    }
  };

  return {
    session,
    status,
    refreshSession,
  };
}
