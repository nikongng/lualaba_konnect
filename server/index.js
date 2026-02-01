const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const fetch = require('node-fetch'); // Importé une seule fois au démarrage

// 1. Initialisation de Firebase Admin (Uniquement pour l'Auth et Firestore)
if (!process.env.SERVICE_ACCOUNT_JSON) {
  console.error('SERVICE_ACCOUNT_JSON env var is required');
}
try {
  const sa = process.env.SERVICE_ACCOUNT_JSON ? JSON.parse(process.env.SERVICE_ACCOUNT_JSON) : undefined;
  admin.initializeApp({ credential: sa ? admin.credential.cert(sa) : undefined });
} catch (e) {
  console.error('Failed to init admin sdk', e);
  admin.initializeApp();
}

const db = admin.firestore();
const USER_COLLECTIONS = ['classic_users', 'pro_users', 'enterprise_users'];

const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID || '';
const ONE_SIGNAL_REST_KEY = process.env.ONE_SIGNAL_REST_KEY || '';

// Helper pour récupérer les IDs OneSignal dans Firestore
async function getOneSignalPlayersForUid(uid) {
  const players = [];
  for (const col of USER_COLLECTIONS) {
    try {
      const docRef = db.collection(col).doc(uid);
      const s = await docRef.get();
      if (!s.exists) continue;
      
      const data = s.data() || {};
      if (data.oneSignalPlayerId) players.push(data.oneSignalPlayerId);
      
      // Vérification de la sous-collection notification_players
      try {
        const sub = await docRef.collection('notification_players').get();
        sub.docs.forEach(d => {
          const td = d.data() || {};
          if (td.playerId) players.push(td.playerId);
        });
      } catch (e) { /* ignore */ }
      
      break; // Utilisateur trouvé dans une collection, on arrête de chercher
    } catch (e) { console.warn(`Error searching in ${col}`, e); }
  }
  return Array.from(new Set(players.filter(Boolean)));
}

const app = express();
app.use(cors());
app.use(express.json());

// simple health endpoint to verify service is reachable
app.get('/', (req, res) => res.json({ ok: true, service: 'notifier' }));

// Santé du service
app.get('/', (req, res) => res.json({ ok: true, service: 'notifier', mode: 'onesignal_only' }));

// Route d'envoi
app.post('/sendNotification', async (req, res) => {
  try {
    // A. Authentification
    const auth = req.headers.authorization || '';
    if (!auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Missing token' });
    
    const idToken = auth.split('Bearer ')[1];
    const caller = await admin.auth().verifyIdToken(idToken);
    if (!caller) return res.status(403).json({ error: 'Invalid token' });

    // B. Validation des données reçues
    const { recipients, title, body, data } = req.body;
    if (!recipients || !Array.isArray(recipients)) return res.status(400).json({ error: 'recipients required' });

    // C. Recherche des IDs OneSignal
    let allPlayers = [];
    for (const uid of recipients) {
      const p = await getOneSignalPlayersForUid(uid);
      allPlayers = [...allPlayers, ...p];
    }
    const players = Array.from(new Set(allPlayers));

    if (players.length === 0) {
      return res.status(404).json({ error: 'no_onesignal_ids_found' });
    }

    // D. Envoi via l'API REST de OneSignal
    const payload = {
      app_id: ONE_SIGNAL_APP_ID,
      include_player_ids: players,
      headings: { en: title || 'Lualaba Konnect' },
      contents: { en: body || '' },
      data: { ...data, sentBy: caller.uid }
    };

    const resp = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${ONE_SIGNAL_REST_KEY}`
      },
      body: JSON.stringify(payload)
    });

    const result = await resp.json();
    return res.json({ ok: true, result });

  } catch (e) {
    console.error('Final Error:', e.message);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

const port = process.env.PORT || 10000;
app.listen(port, () => console.log('Server Live on port', port));