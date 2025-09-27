import { signIn } from "@/app/(auth)/auth";
import { authenticateWalletUser } from '@/lib/auth/wallet-auth';
import { isDevelopmentEnvironment } from "@/lib/constants";
import { getToken } from "next-auth/jwt";
import { type NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
  try {
    const { address, signature, message } = await request.json();

    if (!address || !signature || !message) {
      return NextResponse.json(
        { success: false, error: 'Missing required fields' },
        { status: 400 },
      );
    }

    // Authenticate the wallet user
    const user = await authenticateWalletUser({
      address,
      signature,
      message,
    });

    if (!user) {
      return NextResponse.json(
        { success: false, error: 'Invalid signature or authentication failed' },
        { status: 401 },
      );
    }

    return NextResponse.json({
      success: true,
      user: {
        id: user.id,
        walletAddress: user.walletAddress,
        type: user.type,
      },
    });
  } catch (error) {
    console.error('Wallet authentication error:', error);
    return NextResponse.json(
      { success: false, error: 'Internal server error' },
      { status: 500 },
    );
  }
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const redirectUrl = searchParams.get("redirectUrl") || "/";

  const token = await getToken({
    req: request,
    secret: process.env.AUTH_SECRET,
    secureCookie: !isDevelopmentEnvironment,
  });

  if (token) {
    return NextResponse.redirect(new URL(redirectUrl, request.url));
  }

  // Return a simple response - the frontend will handle wallet connection
  return NextResponse.json({
    message: "Wallet authentication required",
    redirectUrl: redirectUrl
  });
}

