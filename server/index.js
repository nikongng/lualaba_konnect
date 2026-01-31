const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');

// Initialize admin with service account JSON passed via env var SERVICE_ACCOUNT_JSON (stringified)
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

// helper to get OneSignal player ids for a user (checks field and subcollection 'notification_players')
async function getOneSignalPlayersForUid(uid) {
  const players = [];
  for (const col of USER_COLLECTIONS) {
    try {
      const s = await db.collection(col).doc(uid).get();
      if (!s.exists) continue;
      const data = s.data() || {};
      if (data.oneSignalPlayerId) players.push(data.oneSignalPlayerId);
      try {
        const sub = await db.collection(col).doc(uid).collection('notification_players').get();
        for (const d of sub.docs) {
          const td = d.data() || {};
          if (td.playerId) players.push(td.playerId);
        }
      } catch (e) { /* ignore */ }
      break;
    } catch (e) { console.warn('getOneSignalPlayersForUid error', e); }
  }
  return Array.from(new Set(players.filter(Boolean)));
}

async function getTokensForUid(uid) {
  const tokens = [];
  for (const col of USER_COLLECTIONS) {
    try {
      const s = await db.collection(col).doc(uid).get();
      if (!s.exists) continue;
      const data = s.data() || {};
      if (Array.isArray(data.fcmTokens)) tokens.push(...data.fcmTokens.filter(Boolean));
      if (data.fcmToken) tokens.push(data.fcmToken);
      try {
        const sub = await db.collection(col).doc(uid).collection('fcm_tokens').get();
        for (const d of sub.docs) {
          const td = d.data() || {};
          if (td.token) tokens.push(td.token);
        }
      } catch (e) { /* ignore */ }
      break;
    } catch (e) { console.warn('getTokensForUid error', e); }
  }
  return Array.from(new Set(tokens.filter(Boolean)));
}

const app = express();
app.use(cors());
app.use(express.json());

// Secure endpoint: require Firebase ID token in Authorization header
app.post('/sendNotification', async (req, res) => {
  try {
    const auth = req.headers.authorization || '';
    if (!auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Missing id token' });
    const idToken = auth.split('Bearer ')[1];
    const caller = await admin.auth().verifyIdToken(idToken);
    if (!caller || !caller.uid) return res.status(403).json({ error: 'Invalid id token' });

    const { recipients, title, body, data } = req.body;
    if (!recipients || !Array.isArray(recipients) || recipients.length === 0) return res.status(400).json({ error: 'recipients required' });

    // Try OneSignal first if configured
    if (ONE_SIGNAL_APP_ID && ONE_SIGNAL_REST_KEY) {
      try {
        const allPlayers = [];
        for (const uid of recipients) {
          const p = await getOneSignalPlayersForUid(uid);
          for (const x of p) allPlayers.push(x);
        }
        const players = Array.from(new Set(allPlayers.filter(Boolean)));
        if (players.length > 0) {
          // send via OneSignal REST API
          const payload = {
            app_id: ONE_SIGNAL_APP_ID,
            include_player_ids: players,
            headings: { en: title || 'Notification' },
            contents: { en: body || '' },
            data: Object.assign({ sentBy: caller.uid }, data || {})
          };
          const fetch = require('node-fetch');
          const resp = await fetch('https://onesignal.com/api/v1/notifications', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': `Basic ${ONE_SIGNAL_REST_KEY}`
            },
            body: JSON.stringify(payload)
          });
          const json = await resp.json();
          return res.json({ ok: true, provider: 'onesignal', result: json });
        }
      } catch (e) {
        console.warn('OneSignal send failed, falling back to FCM', e);
      }
    }

    // Fallback: use Firebase tokens
    const allTokens = [];
    for (const uid of recipients) {
      const tks = await getTokensForUid(uid);
      for (const t of tks) allTokens.push(t);
    }
    const tokens = Array.from(new Set(allTokens.filter(Boolean)));
    if (tokens.length === 0) return res.json({ ok: true, sent: 0 });

    const msg = {
      tokens,
      notification: { title: title || 'Notification', body: body || '' },
      data: Object.assign({ sentBy: caller.uid }, data || {})
    };
    const resp = await admin.messaging().sendMulticast(msg);
    return res.json({ ok: true, provider: 'fcm', results: resp });
  } catch (e) {
    console.error('sendNotification error', e);
    return res.status(500).json({ error: e.message });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log('Notifier running on', port));
