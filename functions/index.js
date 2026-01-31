const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

admin.initializeApp();
const db = admin.firestore();
const USER_COLLECTIONS = ['classic_users', 'pro_users', 'enterprise_users'];

// Helper: collect FCM tokens for a user (checks fields and subcollection fcm_tokens)
async function getTokensForUid(uid) {
  const tokens = [];
  for (const col of USER_COLLECTIONS) {
    try {
      const s = await db.collection(col).doc(uid).get();
      if (!s.exists) continue;
      const data = s.data() || {};
      if (Array.isArray(data.fcmTokens)) tokens.push(...data.fcmTokens.filter(Boolean));
      if (data.fcmToken) tokens.push(data.fcmToken);
      // also check subcollection fcm_tokens
      try {
        const sub = await db.collection(col).doc(uid).collection('fcm_tokens').get();
        for (const d of sub.docs) {
          const td = d.data() || {};
          if (td.token) tokens.push(td.token);
        }
      } catch (e) {
        console.warn('Error reading fcm_tokens subcollection', e);
      }
      break; // stop after finding the user doc
    } catch (e) {
      console.warn('getTokensForUid error', e);
    }
  }
  return Array.from(new Set(tokens.filter(Boolean)));
}

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// Protect this endpoint: only callers with custom claim `admin: true` can approve requests.
app.post('/approveAdmin', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) return res.status(401).json({ message: 'Missing Bearer token' });
    const idToken = authHeader.split('Bearer ')[1];
    const caller = await admin.auth().verifyIdToken(idToken);
    if (!caller || !caller.admin) return res.status(403).json({ message: 'Forbidden: caller not admin' });

    const { requestId, uid } = req.body;
    if (!requestId || !uid) return res.status(400).json({ message: 'requestId and uid required' });

    // Set custom claim
    await admin.auth().setCustomUserClaims(uid, { admin: true });

    // Update request document
    const reqRef = db.collection('admin_requests').doc(requestId);
    await reqRef.update({ status: 'approved', approvedBy: caller.uid, approvedAt: admin.firestore.FieldValue.serverTimestamp() });

    return res.json({ ok: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: err.message || 'Internal error' });
  }
});

// Simple endpoint to list pending requests (admin-only)
app.get('/listRequests', async (req, res) => {
  try {
    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) return res.status(401).json({ message: 'Missing Bearer token' });
    const idToken = authHeader.split('Bearer ')[1];
    const caller = await admin.auth().verifyIdToken(idToken);
    if (!caller || !caller.admin) return res.status(403).json({ message: 'Forbidden: caller not admin' });

    const snapshot = await db.collection('admin_requests').where('status', '==', 'pending').orderBy('requestedAt', 'desc').limit(100).get();
    const items = snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
    return res.json({ items });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ message: err.message || 'Internal error' });
  }
});

// Export as a Cloud Function for emulator / deployment
exports.api = functions.https.onRequest(app);

// Send FCM when a message is created in 'messages' subcollection or top-level messages
exports.onMessageCreate = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    if (!message) return null;

    const chatId = context.params.chatId;
    const sender = message.senderId || 'unknown';
    const text = message.text || (message.type === 'audio' ? 'Message audio' : 'Nouveau message');

    // find chat doc to get participants
    const chatDoc = await db.collection('chats').doc(chatId).get();
    if (!chatDoc.exists) return null;
    const chat = chatDoc.data() || {};
    const participants = chat.participants || [];
    const userTypes = (chat.userTypes && typeof chat.userTypes === 'object') ? chat.userTypes : {};

    // prepare notification for other participants (collect tokens for each participant)
    const tokensSet = new Set();
    for (const uid of participants) {
      if (uid === sender) continue;
      try {
        const tks = await getTokensForUid(uid);
        for (const t of tks) tokensSet.add(t);
      } catch (e) { console.warn('Error collecting tokens for', uid, e); }
    }
    const tokens = Array.from(tokensSet);
    if (tokens.length === 0) return null;

    const messagePayload = {
      tokens,
      notification: { title: 'Nouvelle discussion', body: text },
      data: { type: 'message', chatId: chatId, senderId: sender }
    };

    try {
      const resp = await admin.messaging().sendMulticast(messagePayload);
      // cleanup invalid tokens: remove token from any user docs (fcmTokens / fcmToken) and delete subcollection doc if present
      for (let i = 0; i < resp.responses.length; i++) {
        const r = resp.responses[i];
        if (!r.success) {
          const badToken = tokens[i];
          if (!badToken) continue;
          console.warn('FCM send error for token', badToken, r.error && r.error.code ? r.error.code : r.error);
          for (const col of USER_COLLECTIONS) {
            try {
              const q = await db.collection(col).where('fcmTokens', 'array-contains', badToken).get();
              for (const doc of q.docs) {
                try { await doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
              const q2 = await db.collection(col).where('fcmToken', '==', badToken).get();
              for (const doc of q2.docs) {
                try { await doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
            } catch (e) { console.error('Error cleaning bad token', badToken, e); }
          }
        }
      }
    } catch (err) {
      console.error('Error sending message FCM', err);
    }
    return null;
  });

// Send FCM when a pending alert is created for a user
exports.onPendingAlertCreate = functions.firestore
  .document('user_alerts/{uid}/pending/{msgId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;
    const toUid = context.params.uid;
    const chatId = data.chatId || null;
    const fromName = data.fromName || 'Un proche';
    const fromUid = data.fromUid || '';

    // find user's fcm tokens across collections
    let userDoc = null;
    for (const col of USER_COLLECTIONS) {
      const s = await db.collection(col).doc(toUid).get();
      if (s.exists) { userDoc = s.data() || {}; break; }
    }
    if (!userDoc) return null;

    const tokens = await getTokensForUid(toUid);
    if (!tokens || tokens.length === 0) return null;

    const title = `Alerte de ${fromName}`;
    const body = `Alerte ! je suis en danger — appuyez pour ouvrir la conversation`;

    const messagePayload = {
      tokens,
      notification: { title: title, body: body },
      data: { type: 'alert', chatId: chatId || '', fromUid: fromUid, msgId: context.params.msgId }
    };

    try {
      const resp = await admin.messaging().sendMulticast(messagePayload);
      // cleanup invalid tokens
      for (let i = 0; i < resp.responses.length; i++) {
        const r = resp.responses[i];
        if (!r.success) {
          const badToken = tokens[i];
          if (!badToken) continue;
          for (const col of USER_COLLECTIONS) {
            try {
              const q = await db.collection(col).where('fcmTokens', 'array-contains', badToken).get();
              for (const doc of q.docs) {
                try { await doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
              const q2 = await db.collection(col).where('fcmToken', '==', badToken).get();
              for (const doc of q2.docs) {
                try { await doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
            } catch (e) { console.error('Error cleaning bad token', badToken, e); }
          }
        }
      }
    } catch (err) {
      console.error('Error sending pending alert FCM', err);
    }
    return null;
  });

  // Scheduled cleanup: normalize tokens and remove empty/duplicate entries
  exports.cleanFcmTokens = functions.pubsub.schedule('every 24 hours').onRun(async (_context) => {
    console.log('Starting cleanFcmTokens job');
    for (const col of USER_COLLECTIONS) {
      const snaps = await db.collection(col).get();
      for (const doc of snaps.docs) {
        const data = doc.data() || {};
        let changed = false;
        // migrate single fcmToken -> fcmTokens
        if (data.fcmToken && !data.fcmTokens) {
          data.fcmTokens = Array.isArray(data.fcmToken) ? data.fcmToken : [data.fcmToken];
          delete data.fcmToken;
          changed = true;
        }
        if (Array.isArray(data.fcmTokens)) {
          // remove falsy and duplicates
          const cleaned = Array.from(new Set(data.fcmTokens.filter(Boolean)));
          if (cleaned.length !== data.fcmTokens.length) {
            data.fcmTokens = cleaned;
            changed = true;
          }
        }
        if (changed) {
          try { await doc.ref.update({ fcmTokens: data.fcmTokens || admin.firestore.FieldValue.delete(), fcmToken: admin.firestore.FieldValue.delete() }); }
          catch (e) { console.warn('Error updating tokens for', doc.id, e); }
        }
      }
    }
    console.log('cleanFcmTokens job finished');
    return null;
  });

// Send FCM when a call doc is created
exports.onCallCreate = functions.firestore
  .document('calls/{callId}')
  .onCreate(async (snap, context) => {
    const call = snap.data();
    if (!call) return null;
    const callee = call.callee;
    const callerName = call.callerName || 'Appelant';

    // find callee across possible collections
    let userData = null;
    for (const col of USER_COLLECTIONS) {
      const s = await db.collection(col).doc(callee).get();
      if (s.exists) { userData = s.data() || {}; break; }
    }
    if (!userData) return null;
    const tokens = await getTokensForUid(callee);
    if (!tokens || tokens.length === 0) return null;

    const messagePayload = {
      tokens,
      notification: { title: 'Appel entrant', body: `${callerName} vous appelle` },
      data: { type: 'call', callId: context.params.callId, callerId: call.caller }
    };

    try {
      const resp = await admin.messaging().sendMulticast(messagePayload);
      for (let i = 0; i < resp.responses.length; i++) {
        const r = resp.responses[i];
        if (!r.success) {
          const badToken = tokens[i];
          if (!badToken) continue;
          for (const col of USER_COLLECTIONS) {
            try {
              const q = await db.collection(col).where('fcmTokens', 'array-contains', badToken).get();
              for (const doc of q.docs) {
                try { await doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
              const q2 = await db.collection(col).where('fcmToken', '==', badToken).get();
              for (const doc of q2.docs) {
                try { await doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
            } catch (e) { console.error('Error cleaning bad token', badToken, e); }
          }
        }
      }
    } catch (err) {
      console.error('Error sending call FCM', err);
    }
    return null;
  });

// Notify sellers and buyer when a market order is created
exports.onMarketOrderCreate = functions.firestore
  .document('market_orders/{orderId}')
  .onCreate(async (snap, context) => {
    const order = snap.data();
    if (!order) return null;
    const orderId = context.params.orderId;
    const items = Array.isArray(order.items) ? order.items : [];
    const buyerUid = order.buyerUid || null;

    // Build map ownerUid -> [items]
    const ownerItems = {};
    for (const it of items) {
      try {
        const prodId = it.id;
        if (!prodId) continue;
        const prodSnap = await db.collection('market_products').doc(prodId).get();
        if (!prodSnap.exists) continue;
        const prod = prodSnap.data() || {};
        const owner = prod.owner || null;
        if (!owner) continue;
        if (!ownerItems[owner]) ownerItems[owner] = [];
        ownerItems[owner].push({ productId: prodId, name: it.name || prod.name || '', quantity: it.quantity || 1 });
      } catch (e) {
        console.warn('Error resolving product owner', e);
      }
    }

    // Notify each seller
    for (const ownerUid of Object.keys(ownerItems)) {
      try {
        // find owner across collections
        let userDoc = null;
        for (const col of USER_COLLECTIONS) {
          const s = await db.collection(col).doc(ownerUid).get();
          if (s.exists) { userDoc = s.data() || {}; break; }
        }
        if (!userDoc) continue;

        const tokens = await getTokensForUid(ownerUid);
        if (!tokens || tokens.length === 0) continue;

        const itemCount = ownerItems[ownerUid].reduce((s, x) => s + (x.quantity || 1), 0);
        const title = 'Nouvelle commande';
        const body = `Vous avez une nouvelle commande (${itemCount} article${itemCount>1?'s':''})`;

        const messagePayload = {
          tokens,
          notification: { title, body },
          data: { type: 'market_order', orderId: orderId, ownerUid: ownerUid }
        };

        const resp = await admin.messaging().sendMulticast(messagePayload);
        // cleanup invalid tokens similar to other handlers
        for (let i = 0; i < resp.responses.length; i++) {
          const r = resp.responses[i];
          if (!r.success) {
            const badToken = tokens[i];
            if (!badToken) continue;
            for (const col of USER_COLLECTIONS) {
              try {
                const q = await db.collection(col).where('fcmTokens', 'array-contains', badToken).get();
                for (const doc of q.docs) {
                  try { await doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) }); } catch (_) {}
                  try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
                }
                const q2 = await db.collection(col).where('fcmToken', '==', badToken).get();
                for (const doc of q2.docs) {
                  try { await doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }); } catch (_) {}
                  try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
                }
              } catch (e) { console.error('Error cleaning bad token for owner', ownerUid, e); }
            }
          }
        }
      } catch (e) {
        console.error('Error notifying seller', e);
      }
    }

    // Notify buyer with confirmation
    if (buyerUid) {
      try {
        let buyerDoc = null;
        for (const col of USER_COLLECTIONS) {
          const s = await db.collection(col).doc(buyerUid).get();
          if (s.exists) { buyerDoc = s.data() || {}; break; }
        }
        if (buyerDoc) {
          const tokens = await getTokensForUid(buyerUid);
          if (tokens && tokens.length > 0) {
            const messagePayload = {
              tokens,
              notification: { title: 'Commande reçue', body: 'Votre commande a bien été enregistrée' },
              data: { type: 'market_order_confirm', orderId: orderId }
            };
            await admin.messaging().sendMulticast(messagePayload);
          }
        }
      } catch (e) { console.error('Error notifying buyer', e); }
    }

    return null;
  });

// Send FCM when a market message is created
exports.onMarketMessageCreate = functions.firestore
  .document('market_messages/{msgId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;

    const toUid = data.to || null;
    if (!toUid) return null;

    const tokens = await getTokensForUid(toUid);
    if (!tokens || tokens.length === 0) return null;

    const title = data.productName || 'Nouveau message';
    const body = data.content || '';

    const messagePayload = {
      tokens,
      notification: { title, body },
      data: {
        type: 'market_message',
        productId: data.productId || '',
        from: data.from || '',
        msgId: context.params.msgId,
      }
    };

    try {
      const resp = await admin.messaging().sendMulticast(messagePayload);
      // cleanup invalid tokens
      for (let i = 0; i < resp.responses.length; i++) {
        const r = resp.responses[i];
        if (!r.success) {
          const badToken = tokens[i];
          if (!badToken) continue;
          for (const col of USER_COLLECTIONS) {
            try {
              const q = await db.collection(col).where('fcmTokens', 'array-contains', badToken).get();
              for (const doc of q.docs) {
                try { await doc.ref.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
              const q2 = await db.collection(col).where('fcmToken', '==', badToken).get();
              for (const doc of q2.docs) {
                try { await doc.ref.update({ fcmToken: admin.firestore.FieldValue.delete() }); } catch (_) {}
                try { const sub = await doc.ref.collection('fcm_tokens').doc(badToken).get(); if (sub.exists) await sub.ref.delete(); } catch (_) {}
              }
            } catch (e) { console.error('Error cleaning bad token', badToken, e); }
          }
        }
      }
    } catch (err) {
      console.error('Error sending market message FCM', err);
    }

    return null;
  });
