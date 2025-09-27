import { createSlice, type PayloadAction } from '@reduxjs/toolkit';

interface UserAccountDetails {
  walletAddress: string | null;
  isAuthenticated: boolean;
  authTimestamp: number | null;
}

const initialState: UserAccountDetails = {
  walletAddress: null,
  isAuthenticated: false,
  authTimestamp: null,
};

const userAccountDetailsSlice = createSlice({
  name: 'userAccountDetails',
  initialState,
  reducers: {
    setWalletAddress: (state, action: PayloadAction<string | null>) => {
      state.walletAddress = action.payload;
    },
    clearWalletAddress: (state) => {
      state.walletAddress = null;
      state.isAuthenticated = false;
      state.authTimestamp = null;
    },
    setAuthenticated: (state, action: PayloadAction<boolean>) => {
      state.isAuthenticated = action.payload;
      state.authTimestamp = action.payload ? Date.now() : null;
    },
  },
});

export const { setWalletAddress, clearWalletAddress, setAuthenticated } =
  userAccountDetailsSlice.actions;
export default userAccountDetailsSlice.reducer;
