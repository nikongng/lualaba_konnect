const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const USER_COLLECTIONS = ['classic_users', 'pro_users', 'enterprise_users'];

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

    // prepare notification for other participants (support single token or array of tokens)
    const tokenOwners = [];
    for (const uid of participants) {
      if (uid === sender) continue;
      // detect which collection the user belongs to (use chat.userTypes mapping if present)
      const preferredCol = userTypes[uid] || null;
      const colsToTry = preferredCol ? [preferredCol, ...USER_COLLECTIONS.filter(c=>c!==preferredCol)] : USER_COLLECTIONS;
      let u = null;
      for (const col of colsToTry) {
        const userSnap = await db.collection(col).doc(uid).get();
        if (userSnap.exists) { u = userSnap.data() || {}; break; }
      }
      if (!u) continue;
      if (Array.isArray(u.fcmTokens)) {
        for (const t of u.fcmTokens) tokenOwners.push({ uid, token: t });
      } else if (u.fcmToken) {
        tokenOwners.push({ uid, token: u.fcmToken });
      }
    }

    const tokens = tokenOwners.map(o => o.token).filter(Boolean);
    if (tokens.length === 0) return null;

    const messagePayload = {
      tokens,
      notification: { title: 'Nouvelle discussion', body: text },
      data: { type: 'message', chatId: chatId, senderId: sender }
    };

    try {
      const resp = await admin.messaging().sendMulticast(messagePayload);
      // cleanup invalid tokens
      for (let i = 0; i < resp.responses.length; i++) {
        const r = resp.responses[i];
        if (!r.success) {
          const err = r.error;
          const badToken = tokens[i];
          const owner = tokenOwners[i];
          if (!badToken || !owner) continue;
          const reason = err && err.code ? err.code : (err && err.message) || 'unknown';
          console.warn('FCM send error for token', badToken, reason);
          // remove token from user doc (array or single field)
          const userRef = db.collection('classic_users').doc(owner.uid);
          try {
            await userRef.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) });
            const fresh = await userRef.get();
            const data = fresh.data() || {};
            if (data.fcmToken === badToken) {
              await userRef.update({ fcmToken: admin.firestore.FieldValue.delete() });
            }
          } catch (e) {
            console.error('Error cleaning bad token for user', owner.uid, e);
          }
        }
      }
    } catch (err) {
      console.error('Error sending message FCM', err);
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
    const u = userData;
    const tokenOwners = [];
    if (Array.isArray(u.fcmTokens)) {
      for (const t of u.fcmTokens) tokenOwners.push({ uid: callee, token: t });
    } else if (u.fcmToken) {
      tokenOwners.push({ uid: callee, token: u.fcmToken });
    }
    const tokens = tokenOwners.map(o => o.token).filter(Boolean);
    if (tokens.length === 0) return null;

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
          const owner = tokenOwners[i];
          if (!badToken || !owner) continue;
          const userRef = db.collection('classic_users').doc(owner.uid);
          try {
            await userRef.update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(badToken) });
            const fresh = await userRef.get();
            const data = fresh.data() || {};
            if (data.fcmToken === badToken) {
              await userRef.update({ fcmToken: admin.firestore.FieldValue.delete() });
            }
          } catch (e) {
            console.error('Error cleaning bad token for user', owner.uid, e);
          }
        }
      }
    } catch (err) {
      console.error('Error sending call FCM', err);
    }
    return null;
  });
