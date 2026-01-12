/**
 * Usage:
 * 1) Place your Firebase service account JSON at `functions/serviceAccountKey.json`
 *    OR set environment var GOOGLE_APPLICATION_CREDENTIALS to the key path.
 * 2) Run: `node setAdmin.js <UID>`
 *
 * IMPORTANT: do NOT commit the service account file to source control.
 */

const admin = require('firebase-admin');
const fs = require('fs');

const uid = process.argv[2];
if (!uid) {
  console.error('Usage: node setAdmin.js <UID>');
  process.exit(1);
}

const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || './serviceAccountKey.json';
if (!fs.existsSync(keyPath)) {
  console.error(`Service account key not found at ${keyPath}. Place your key at that path or set GOOGLE_APPLICATION_CREDENTIALS.`);
  process.exit(1);
}

const serviceAccount = require(keyPath);

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

admin.auth().setCustomUserClaims(uid, { admin: true })
  .then(() => {
    console.log(`Custom claim 'admin:true' set for UID=${uid}`);
    console.log('The user may need to sign out and sign in again for the token to refresh.');
    process.exit(0);
  })
  .catch((err) => {
    console.error('Error setting custom claim:', err);
    process.exit(1);
  });
