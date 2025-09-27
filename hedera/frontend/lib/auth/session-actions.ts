'use server';

import { auth, signOut } from '@/app/(auth)/auth';
import { revalidatePath } from 'next/cache';

/**
 * Server action to clear session and revalidate paths
 * This ensures server-side session is properly cleared
 */
export async function clearUserSession() {
  try {
    // Get current session
    const session = await auth();
    
    if (session) {
      // Sign out the user
      await signOut({ redirect: false });
    }
    
    // Revalidate all paths to clear cached data
    revalidatePath('/', 'layout');
    revalidatePath('/chat', 'page');
    
    return { success: true };
  } catch (error) {
    console.error('Error clearing session:', error);
    return { success: false, error: 'Failed to clear session' };
  }
}
