import { initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider, OAuthProvider } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getFunctions } from "firebase/functions";

/**
 * Reuses the exact same `shui-prod` Firebase project the iOS app talks
 * to — this dashboard is a second client, not a second backend. Config
 * comes from a Web app registered in the Firebase console (Project
 * settings > General > Your apps > Add app > Web), which is a manual
 * console step nothing in this repo can do on your behalf. See
 * web/.env.example for what to fill in.
 */
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app);

export const googleProvider = new GoogleAuthProvider();
/** Firebase's generic OAuth provider, configured for Sign in with Apple. */
export const appleProvider = new OAuthProvider("apple.com");
