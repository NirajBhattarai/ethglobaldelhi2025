import { authenticateWalletUser } from "@/lib/auth/wallet-auth";
import { DUMMY_PASSWORD } from "@/lib/constants";
import { createGuestUser, getUser, getUserByWalletAddress } from "@/lib/db/queries";
import { compare } from "bcrypt-ts";
import NextAuth, { type DefaultSession } from "next-auth";
import type { DefaultJWT } from "next-auth/jwt";
import Credentials from "next-auth/providers/credentials";
import { authConfig } from "./auth.config";

export type UserType = "guest" | "regular" | "wallet";

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
    email?: string | null;
    walletAddress?: string | null;
    type: UserType;
  }
}

declare module "next-auth/jwt" {
  interface JWT extends DefaultJWT {
    id: string;
    type: UserType;
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
    Credentials({
      id: "guest",
      credentials: {},
      async authorize() {
        const [guestUser] = await createGuestUser();
        return { ...guestUser, type: "guest" };
      },
    }),
  ],
  callbacks: {
    jwt({ token, user }) {
      if (user) {
        token.id = user.id as string;
        token.type = user.type;
      }

      return token;
    },
    session({ session, token }) {
      if (session.user) {
        session.user.id = token.id;
        session.user.type = token.type;
      }

      return session;
    },
  },
});
