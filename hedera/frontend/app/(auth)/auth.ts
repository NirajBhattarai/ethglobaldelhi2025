import { authenticateWalletUser } from "@/lib/auth/wallet-auth";
import NextAuth, { type DefaultSession } from "next-auth";
import type { DefaultJWT } from "next-auth/jwt";
import Credentials from "next-auth/providers/credentials";
import { authConfig } from "./auth.config";

export type UserType = "wallet";

declare module "next-auth" {
  interface Session extends DefaultSession {
    user: {
      id: string;
      type: UserType;
    } & DefaultSession["user"];
  }

  // biome-ignore lint/nursery/useConsistentTypeDefinitions: "Required"
  interface User {
    id?: string;
    walletAddress?: string | null;
    type: UserType;
  }
}

declare module "next-auth/jwt" {
  interface JWT extends DefaultJWT {
    id: string;
    type: UserType;
     walletAddress?: string;
  }
}

export const {
  handlers: { GET, POST },
  auth,
  signIn,
  signOut,
} = NextAuth({
  ...authConfig,
  providers: [
     Credentials({
      id: 'wallet',
      credentials: {},
      async authorize({ address, signature, message }: any) {
        if (!address || !signature || !message) {
          return null;
        }

        const user = await authenticateWalletUser({
          address,
          signature,
          message,
        });

        if (!user) {
          return null;
        }

        return {
          id: user.id,
          walletAddress: user.walletAddress,
          type: 'wallet',
        };
      },
    }),
  ],
  callbacks: {
    jwt({ token, user }) {
      if (user) {
        token.id = user.id as string;
        token.type = user.type;
        if (user.walletAddress) {
          token.walletAddress = user.walletAddress;
        }
      }

      return token;
    },
    session({ session, token }) {
      if (session.user) {
        session.user.id = token.id;
        session.user.type = token.type;
        if (token.walletAddress) {
          session.user.walletAddress = token.walletAddress;
        }
      }

      return session;
    },
  },
});
