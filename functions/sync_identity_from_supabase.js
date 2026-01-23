const admin = require('firebase-admin');
const fs = require('fs');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://givptuedrwtudwgwxwep.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';
const SERVICE_KEY = process.env.GOOGLE_APPLICATION_CREDENTIALS || './lualaba-konnect-firebase-adminsdk-fbsvc-efe520ce27.json';

if (!fs.existsSync(SERVICE_KEY)) {
  console.error('Service account key not found at', SERVICE_KEY);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(SERVICE_KEY)) });
const db = admin.firestore();

async function listSupabaseFiles() {
  const url = `${SUPABASE_URL}/storage/v1/object/list/IDENTITY`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({ prefix: '', limit: 2000 }),
  });
  if (!res.ok) throw new Error('Failed to list supabase objects: ' + res.statusText);
  const data = await res.json();
  return data;
}

async function run() {
  try {
    console.log('Listing files in Supabase bucket IDENTITY...');
    const items = await listSupabaseFiles();
    if (!Array.isArray(items)) {
      console.error('Unexpected response:', items);
      process.exit(1);
    }

    // build uid -> collection map
    const collections = ['classic_users', 'pro_users', 'enterprise_users'];
    const uidToCol = {};
    for (const col of collections) {
      const snaps = await db.collection(col).get();
      snaps.forEach(s => { uidToCol[s.id] = col; });
    }

    const results = [];
    for (const obj of items) {
      const name = obj.name || obj.id || obj; // adapt to shape
      if (!name) continue;
      const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/IDENTITY/${encodeURIComponent(name)}`;

      // try to find uid in filename
      const matchedUid = Object.keys(uidToCol).find(u => name.includes(u));
      if (matchedUid) {
        const col = uidToCol[matchedUid];
        const lower = name.toLowerCase();
        const isPdf = lower.endsWith('.pdf') || lower.includes('identity') || lower.includes('id');
        const isImage = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.includes('selfie');
        const update = {};
        if (isImage) update['documents.selfie'] = publicUrl;
        if (isPdf) update['documents.identityPdf'] = publicUrl;
        if (!isImage && !isPdf) {
          // fallback: if name contains 'selfie' treat as selfie
          if (lower.includes('selfie')) update['documents.selfie'] = publicUrl;
          else update['documents.identityPdf'] = publicUrl;
        }

        try {
          await db.collection(col).doc(matchedUid).set({ documents: update }, { merge: true });
          console.log(`Updated ${col}/${matchedUid} with ${JSON.stringify(update)}`);
          results.push({ name, matchedUid, col, update });
        } catch (e) {
          console.error('Error updating firestore for', matchedUid, e);
        }
      } else {
        // no uid match — save to list for manual inspection
        results.push({ name, publicUrl, matchedUid: null });
      }
    }

    const out = { generatedAt: new Date().toISOString(), count: results.length, items: results };
    fs.writeFileSync('./functions/supabase_identity_list.json', JSON.stringify(out, null, 2));
    console.log('Wrote functions/supabase_identity_list.json — review items with matchedUid==null for manual mapping.');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(1);
  }
}

run();
