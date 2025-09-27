import { configureStore } from '@reduxjs/toolkit';
import {
  persistStore,
  persistReducer,
  FLUSH,
  REHYDRATE,
  PAUSE,
  PERSIST,
  PURGE,
  REGISTER,
} from 'redux-persist';
import storage from 'redux-persist/lib/storage';
import userAccountDetailsReducer from './features/userAccountDetailsSlice';

const persistConfig = {
  key: 'root',
  storage,
  whitelist: ['userAccountDetails'],
};

const persistedUserAccountDetailsReducer = persistReducer(
  persistConfig,
  userAccountDetailsReducer,
);

export const makeStore = () => {
  return configureStore({
    reducer: {
      userAccountDetails: persistedUserAccountDetailsReducer,
    },
    middleware: (getDefaultMiddleware) =>
      getDefaultMiddleware({
        serializableCheck: {
          ignoredActions: [FLUSH, REHYDRATE, PAUSE, PERSIST, PURGE, REGISTER],
        },
      }),
  });
};

export type AppStore = ReturnType<typeof makeStore>;
export type RootState = ReturnType<AppStore['getState']>;
export type AppDispatch = AppStore['dispatch'];

export const store = makeStore();
export const persistor = persistStore(store);
