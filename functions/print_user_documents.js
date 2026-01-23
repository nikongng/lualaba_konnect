const admin = require('firebase-admin');
const path = require('path');

const SERVICE_KEY = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.join(__dirname, 'lualaba-konnect-firebase-adminsdk-fbsvc-efe520ce27.json');
if (!require('fs').existsSync(SERVICE_KEY)) {
  console.error('Service account JSON not found at', SERVICE_KEY);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(SERVICE_KEY)) });
const db = admin.firestore();

const args = require('minimist')(process.argv.slice(2));
const email = args.email || args.e;
const phone = args.phone || args.p;
if (!email && !phone) {
  console.error('Usage: node print_user_documents.js --email user@example.com OR --phone +243...');
  process.exit(1);
}

const collections = ['classic_users','pro_users','enterprise_users','users'];

async function findAndPrint() {
  for (const col of collections) {
    try {
      let q;
      if (email) q = db.collection(col).where('email','==', email).limit(1);
      else q = db.collection(col).where('phone','==', phone).limit(1);
      const snap = await q.get();
      if (!snap.empty) {
        const doc = snap.docs[0];
        console.log('Found in collection', col, 'docId=', doc.id);
        const data = doc.data();
        console.log('Full document:\n', JSON.stringify(data, null, 2));
        if (data.documents) {
          console.log('\ndocuments field:\n', JSON.stringify(data.documents, null, 2));
        } else {
          console.log('\nNo documents field present on this user.');
        }
        return;
      }
    } catch (e) {
      console.error('Error querying', col, e.message);
    }
  }
  console.error('User not found in collections:', collections.join(','));
}

findAndPrint().then(()=>process.exit(0)).catch(e=>{console.error(e);process.exit(1)});
