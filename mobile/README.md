# ALLways Android App

Flutter Android frontend for ALLways.

- Existing ALLways website remains unchanged.
- Android app uses the same Firebase project/backend.
- Firestore is the shared source of truth for live data.
- Firebase Authentication will be shared between website and app.

## Firebase setup

Add the Android app to the existing Firebase project and place the downloaded google-services.json at:

mobile/android/app/google-services.json

Do not commit Firebase Admin/service-account private keys.
