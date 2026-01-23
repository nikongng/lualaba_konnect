const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const SERVICE_KEY = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.join(__dirname, 'lualaba-konnect-firebase-adminsdk-fbsvc-efe520ce27.json');
if (!fs.existsSync(SERVICE_KEY)) {
  console.error('Service account JSON not found at', SERVICE_KEY);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(SERVICE_KEY)) });
const db = admin.firestore();

const collections = ['classic_users', 'pro_users', 'enterprise_users', 'users'];

function chooseFieldName(key, value) {
  const lk = (key || '').toLowerCase();
  const lv = (value || '').toLowerCase();
  if (lk.includes('selfie') || lk.includes('photo') || lk.includes('avatar')) return 'selfie';
  if (lk.includes('identity') || lk.includes('id') || lk.includes('document')) return 'identityPdf';
  if (lv.includes('selfie')) return 'selfie';
  if (lv.endsWith('.pdf') || lv.includes('.pdf')) return 'identityPdf';
  if (lv.match(/\.(jpg|jpeg|png|gif)$/)) return 'selfie';
  // fallback: if url contains 'identity' keyword
  if (lv.includes('identity')) return 'identityPdf';
  return null;
}

async function run() {
  let totalUpdated = 0;
  for (const col of collections) {
    console.log('Scanning collection', col);
    const snap = await db.collection(col).get();
    for (const docSnap of snap.docs) {
      const data = docSnap.data();
      const updates = {};
      for (const [k, v] of Object.entries(data)) {
        if (typeof v === 'string' && v.includes('supabase.co/storage')) {
          const which = chooseFieldName(k, v);
          if (which === 'selfie') updates['documents.selfie'] = v.trim();
          else if (which === 'identityPdf') updates['documents.identityPdf'] = v.trim();
        }
      }
      if (Object.keys(updates).length > 0) {
        try {
          await db.collection(col).doc(docSnap.id).set({ documents: updates }, { merge: true });
          console.log(`Updated ${col}/${docSnap.id} ->`, updates);
          totalUpdated++;
        } catch (e) {
          console.error('Failed update', col, docSnap.id, e.message);
        }
      }
    }
  }
  console.log('Migration finished. Documents updated:', totalUpdated);
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
