const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const fetch = require('node-fetch');

// 1. Initialisation Firebase Admin
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

// 2. Variables d'environnement (À configurer sur le dashboard Render)
const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID || '';
const ONE_SIGNAL_REST_KEY = process.env.ONE_SIGNAL_REST_KEY || '';
// Optional: explicit Android channel UUIDs created in OneSignal dashboard.
// If not provided, OneSignal will use the default channel.
const ONESIGNAL_ANDROID_CHANNEL_MESSAGES = process.env.ONESIGNAL_ANDROID_CHANNEL_MESSAGES || '';
const ONESIGNAL_ANDROID_CHANNEL_CALLS = process.env.ONESIGNAL_ANDROID_CHANNEL_CALLS || '';
// Optional: custom sounds (names). For Android, the sound must exist in `res/raw` (without extension)
// or be configured via the OneSignal Android channel. For iOS, the sound file must be in the app bundle.
const ONESIGNAL_CALL_ANDROID_SOUND = process.env.ONESIGNAL_CALL_ANDROID_SOUND || '';
const ONESIGNAL_CALL_IOS_SOUND = process.env.ONESIGNAL_CALL_IOS_SOUND || '';
const METERED_API_KEY = process.env.METERED_API_KEY; // Clé récupérée via .env
const METALS_API_KEY = process.env.METALS_API_KEY || '';

// Cache métaux en mémoire (rafraîchit 1 fois/jour)
const metalsCache = {
    data: null,
    fetchedAt: 0,
    asOf: '',
    currency: 'USD',
    unit: 't',
};

function _todayKey() {
    return new Date().toISOString().slice(0, 10);
}

async function _fetchMetalsLME() {
    if (!METALS_API_KEY) {
        throw new Error('METALS_API_KEY missing on server');
    }
    const url = `https://api.metals.dev/v1/latest?api_key=${METALS_API_KEY}&currency=${metalsCache.currency}&unit=${metalsCache.unit}`;
    const resp = await fetch(url);
    if (!resp.ok) {
        const t = await resp.text();
        throw new Error(`Metals API error ${resp.status}: ${t}`);
    }
    const payload = await resp.json();
    const metals = payload && payload.metals ? payload.metals : null;
    if (!metals || typeof metals !== 'object') {
        throw new Error('Metals payload invalid');
    }
    metalsCache.data = metals;
    metalsCache.fetchedAt = Date.now();
    metalsCache.asOf = _todayKey();
    return metals;
}

// Helper pour récupérer les IDs OneSignal
async function getOneSignalPlayersForUid(uid) {
    const players = [];
    for (const col of USER_COLLECTIONS) {
        try {
            const docRef = db.collection(col).doc(uid);
            const s = await docRef.get();
            if (!s.exists) continue;
            const data = s.data() || {};
            if (data.oneSignalPlayerId) players.push(data.oneSignalPlayerId);
            try {
                const sub = await docRef.collection('notification_players').get();
                sub.docs.forEach(d => {
                    const td = d.data() || {};
                    if (td.playerId) players.push(td.playerId);
                });
            } catch (e) {}
            break; 
        } catch (e) { console.warn(`Error searching in ${col}`, e); }
    }
    return Array.from(new Set(players.filter(Boolean)));
}

const app = express();
app.use(cors());
app.use(express.json());

// Endpoint de santé
app.get('/', (req, res) => res.json({ 
    ok: true, 
    service: 'notifier-webrtc-bridge', 
    mode: 'production' 
}));

// --- ROUTE : PRIX METAUX (CACHE JOURNALIER) ---
app.get('/metals-lme', async (req, res) => {
    try {
        const force = req.query.force === '1';
        const today = _todayKey();
        const cacheValid = metalsCache.data && metalsCache.asOf === today;

        if (!force && cacheValid) {
            return res.json({
                ok: true,
                source: 'cache',
                asOf: metalsCache.asOf,
                updatedAt: metalsCache.fetchedAt,
                currency: metalsCache.currency,
                unit: metalsCache.unit,
                metals: metalsCache.data,
            });
        }

        const metals = await _fetchMetalsLME();
        return res.json({
            ok: true,
            source: 'metals.dev',
            asOf: metalsCache.asOf,
            updatedAt: metalsCache.fetchedAt,
            currency: metalsCache.currency,
            unit: metalsCache.unit,
            metals,
        });
    } catch (e) {
        console.error('Metals cache error:', e.message);
        return res.status(500).json({ ok: false, error: 'metals_fetch_failed' });
    }
});

// --- ROUTE : CONFIGURATION WEBRTC DYNAMIQUE (STUN + TURN) ---
// Cette route privilégie STUN (gratuit) et utilise Metered (TURN) en secours
app.get('/webrtc-config', async (req, res) => {
    try {
        if (!METERED_API_KEY) {
            console.error("METERED_API_KEY manquante sur Render");
            // Secours minimal si la clé est absente
            return res.json({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
        }

        // On appelle l'API Metered pour obtenir des identifiants TURN temporaires
        const response = await fetch(`https://mhb.metered.live/api/v1/turn/credentials?apiKey=${METERED_API_KEY}`);
        const turnServers = await response.json();

        // On fusionne : STUN de Google en premier (priorité P2P direct)
        // puis les serveurs TURN de Metered (relais si échec P2P)
        const iceServers = [
            { urls: 'stun:stun.l.google.com:19302' },
            { urls: 'stun:stun1.l.google.com:19302' },
            ...turnServers 
        ];

        res.json({ iceServers });
    } catch (e) {
        console.error("Erreur lors de la génération des accès WebRTC:", e.message);
        res.json({
            iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
        });
    }
});

// --- ROUTE : ENVOI DE NOTIFICATIONS ---
app.post('/sendNotification', async (req, res) => {
    try {
        const auth = req.headers.authorization || '';
        if (!auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Missing token' });
        
        const idToken = auth.split('Bearer ')[1];
        const caller = await admin.auth().verifyIdToken(idToken);
        if (!caller) return res.status(403).json({ error: 'Invalid token' });

        const { recipients, title, body, data } = req.body;
        if (!recipients || !Array.isArray(recipients)) return res.status(400).json({ error: 'recipients required' });

        // Prefer targeting by external user ids (set via OneSignal.login(uid) in the app)
        const externalUserIds = Array.from(new Set(recipients.filter(Boolean)));

        // Optional fallback: legacy player ids if external ids are not available
        let allPlayers = [];
        for (const uid of recipients) {
            const p = await getOneSignalPlayersForUid(uid);
            allPlayers = [...allPlayers, ...p];
        }
        const players = Array.from(new Set(allPlayers));

        if (externalUserIds.length === 0 && players.length === 0) {
            return res.status(404).json({ error: 'no_onesignal_ids_found' });
        }

        const isCall = data && data.type === 'incoming_call';

        const payload = {
            app_id: ONE_SIGNAL_APP_ID,
            ...(externalUserIds.length > 0 ? { include_external_user_ids: externalUserIds, channel_for_external_user_ids: "push" } : {}),
            ...(players.length > 0 ? { include_player_ids: players } : {}),
            headings: { fr: title || 'Lualaba Konnect', en: title || 'Lualaba Konnect' },
            contents: { fr: body || '', en: body || '' },
            large_icon: req.body.senderAvatarUrl || '', 
            big_picture: req.body.imageUrl || '',
            priority: 10,
            android_group: isCall ? "calls_group" : "messages_group",
            // For calls, keep TTL short so stale "incoming call" notifications don't arrive late.
            ttl: isCall ? 35 : 86400,
            buttons: isCall ? [
                { id: "accept", text: "Répondre", icon: "ic_menu_call" },
                { id: "decline", text: "Refuser", icon: "ic_menu_close" }
            ] : [],
            data: { ...data, sentBy: caller.uid }
        };

        // Only set android_channel_id if you provided real channel UUIDs from OneSignal dashboard.
        // Passing an unknown value can cause confusing behavior on some devices.
        const channelId = isCall ? ONESIGNAL_ANDROID_CHANNEL_CALLS : ONESIGNAL_ANDROID_CHANNEL_MESSAGES;
        if (channelId && typeof channelId === 'string' && channelId.trim().length > 0) {
            payload.android_channel_id = channelId.trim();
        }

        // Optional call sounds (recommended to configure on the OneSignal "Calls" channel instead).
        if (isCall) {
            if (ONESIGNAL_CALL_ANDROID_SOUND && typeof ONESIGNAL_CALL_ANDROID_SOUND === 'string' && ONESIGNAL_CALL_ANDROID_SOUND.trim().length > 0) {
                payload.android_sound = ONESIGNAL_CALL_ANDROID_SOUND.trim();
            }
            if (ONESIGNAL_CALL_IOS_SOUND && typeof ONESIGNAL_CALL_IOS_SOUND === 'string' && ONESIGNAL_CALL_IOS_SOUND.trim().length > 0) {
                payload.ios_sound = ONESIGNAL_CALL_IOS_SOUND.trim();
            }
        }

        const resp = await fetch('https://onesignal.com/api/v1/notifications', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Basic ${ONE_SIGNAL_REST_KEY}`
            },
            body: JSON.stringify(payload)
        });

        const raw = await resp.text();
        let result = null;
        try { result = JSON.parse(raw); } catch (_) { result = { raw }; }

        if (!resp.ok) {
            console.error('OneSignal API error:', resp.status, result);
            return res.status(resp.status).json({ ok: false, error: 'onesignal_api_error', result });
        }

        return res.json({ ok: true, result });

    } catch (e) {
        console.error('Notification Error:', e.message);
        return res.status(500).json({ error: 'Internal server error' });
    }
});

const port = process.env.PORT || 10000;
app.listen(port, () => console.log('Server Live on port', port));
