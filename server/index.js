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
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || '';
const CONTENT_AGENT_ENABLED = process.env.CONTENT_AGENT_ENABLED === '1';
const CONTENT_AGENT_SECRET = process.env.CONTENT_AGENT_SECRET || '';
const CONTENT_AGENT_AUTHOR_ID = process.env.CONTENT_AGENT_AUTHOR_ID || 'konnect-agent';
const CONTENT_AGENT_AUTHOR_NAME = process.env.CONTENT_AGENT_AUTHOR_NAME || 'Agent Konnect';
const CONTENT_AGENT_AUTHOR_AVATAR = process.env.CONTENT_AGENT_AUTHOR_AVATAR || '';
const CONTENT_AGENT_GEMINI_ENABLED = process.env.CONTENT_AGENT_GEMINI_ENABLED !== '0';
const CONTENT_AGENT_GEMINI_MODEL = process.env.CONTENT_AGENT_GEMINI_MODEL || 'gemini-2.5-flash';
const CONTENT_AGENT_INTERVAL_MINUTES = Math.max(15, parseInt(process.env.CONTENT_AGENT_INTERVAL_MINUTES || '60', 10) || 60);
const CONTENT_AGENT_MIN_HOURS = Math.max(1, parseInt(process.env.CONTENT_AGENT_MIN_HOURS || '4', 10) || 4);
const CONTENT_AGENT_CREATE_STORY = process.env.CONTENT_AGENT_CREATE_STORY !== '0';
const CONTENT_AGENT_MEDIA_JSON = process.env.CONTENT_AGENT_MEDIA_JSON || '';
const CONTENT_AGENT_FACEBOOK_ENABLED = process.env.CONTENT_AGENT_FACEBOOK_ENABLED === '1';
const FACEBOOK_GRAPH_VERSION = process.env.FACEBOOK_GRAPH_VERSION || 'v21.0';
const FACEBOOK_PAGE_ID = process.env.FACEBOOK_PAGE_ID || '';
const FACEBOOK_PAGE_ACCESS_TOKEN = process.env.FACEBOOK_PAGE_ACCESS_TOKEN || '';
const CONTENT_AGENT_FACEBOOK_LIMIT = Math.max(1, Math.min(25, parseInt(process.env.CONTENT_AGENT_FACEBOOK_LIMIT || '8', 10) || 8));
const CONTENT_AGENT_MESSAGE_BATCH_SIZE = Math.max(1, Math.min(20, parseInt(process.env.CONTENT_AGENT_MESSAGE_BATCH_SIZE || '3', 10) || 3));
const CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS = Math.max(10, parseInt(process.env.CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS || '120', 10) || 120);
const CONTENT_AGENT_MESSAGE_MAX_RECIPIENTS = Math.max(1, Math.min(5000, parseInt(process.env.CONTENT_AGENT_MESSAGE_MAX_RECIPIENTS || '500', 10) || 500));
const CONTENT_AGENT_MESSAGE_TEMPLATES_JSON = process.env.CONTENT_AGENT_MESSAGE_TEMPLATES_JSON || '';

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

const CONTENT_AGENT_POSTS = [
    {
        category: 'Infos Officielles',
        text: 'Point Konnect: gardez vos informations de profil a jour pour faciliter les echanges et les services locaux.',
        story: 'Petit rappel: un profil clair aide la communaute a mieux se connecter.',
    },
    {
        category: 'Communaut\u00e9',
        text: 'Bonjour Lualaba. Partagez aujourd hui une info utile de votre quartier: route, service, opportunite ou bon plan.',
        story: 'Une info locale peut aider quelqu un aujourd hui.',
    },
    {
        category: 'Alertes',
        text: 'Conseil securite: si vous voyez une situation urgente, utilisez les outils d alerte et donnez une description courte et precise.',
        story: 'En cas d urgence, une description precise aide tout le monde.',
    },
    {
        category: 'Buzz',
        text: 'Question du jour: quel service aimeriez vous voir plus actif sur Lualaba Konnect cette semaine ?',
        story: 'Question du jour: quel service voulez vous voir grandir ici ?',
    },
    {
        category: 'Communaut\u00e9',
        text: 'Bienvenue aux nouveaux membres. Ici, meme une petite publication peut lancer une conversation utile.',
        story: 'Bienvenue aux nouveaux membres de Lualaba Konnect.',
    },
    {
        category: 'Infos Officielles',
        text: 'Astuce Konnect: verifiez vos notifications pour ne pas manquer les messages, alertes et demandes importantes.',
        story: 'Pensez a verifier vos notifications Konnect.',
    },
];

function _parseJsonArray(raw, fallback = []) {
    if (!raw || typeof raw !== 'string') return fallback;
    try {
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed : fallback;
    } catch (e) {
        console.warn('Invalid JSON array env:', e.message);
        return fallback;
    }
}

const CONTENT_AGENT_MEDIA_POOL = _parseJsonArray(CONTENT_AGENT_MEDIA_JSON);
const DEFAULT_CONTENT_AGENT_MESSAGE_TEMPLATES = [
    'Bonjour, je suis Agent Konnect. Je passe juste te souhaiter la bienvenue et t aider a decouvrir Lualaba Konnect.',
    'Salut. Si tu veux, publie une petite info locale aujourd hui: route, service, bon plan ou opportunite.',
    'Bonjour. Pense a completer ton profil pour faciliter les echanges avec les autres membres.',
    'Salut, je veille sur les nouveautes de la communaute. Ouvre le fil pour voir les infos recentes.',
    'Bonjour. Si tu as besoin d aide ou d une info locale, tu peux commencer par ecrire dans la communaute.',
    'Petit message de bienvenue: plus les membres partagent des infos utiles, plus Lualaba Konnect devient vivant.',
];
const CONTENT_AGENT_MESSAGE_TEMPLATES = _parseJsonArray(
    CONTENT_AGENT_MESSAGE_TEMPLATES_JSON,
    DEFAULT_CONTENT_AGENT_MESSAGE_TEMPLATES,
).map(_cleanString).filter(Boolean);

function _buildAutonomousAgentMessage() {
    const templates = CONTENT_AGENT_MESSAGE_TEMPLATES.length
        ? CONTENT_AGENT_MESSAGE_TEMPLATES
        : DEFAULT_CONTENT_AGENT_MESSAGE_TEMPLATES;
    const dayKey = Math.floor(Date.now() / (24 * 60 * 60 * 1000));
    const hour = new Date().getHours();
    const prefix = hour < 12 ? 'Bonjour.' : (hour < 18 ? 'Bon apres-midi.' : 'Bonsoir.');
    const selected = templates[dayKey % templates.length];
    return selected.startsWith('Bonjour') || selected.startsWith('Bonsoir') || selected.startsWith('Salut')
        ? selected
        : `${prefix} ${selected}`;
}

async function buildAutonomousAgentMessage(options = {}) {
    try {
        const geminiText = await generateGeminiMessageText(options);
        if (geminiText) {
            return { text: geminiText, source: 'gemini' };
        }
    } catch (e) {
        console.error('Gemini message generation error:', e.message);
    }
    return { text: _buildAutonomousAgentMessage(), source: 'template' };
}

function _cleanString(value) {
    return value == null ? '' : String(value).trim();
}

function _normalizeMediaEntry(raw) {
    if (!raw) return null;
    if (typeof raw === 'string') {
        const url = raw.trim();
        if (!url) return null;
        return { type: _guessMediaType(url), url };
    }
    if (typeof raw !== 'object') return null;
    const url = _cleanString(raw.url || raw.imageUrl || raw.videoUrl || raw.fileUrl || raw.src);
    if (!url) return null;
    const rawType = _cleanString(raw.type || raw.mediaType).toLowerCase();
    const type = ['image', 'video', 'audio', 'file'].includes(rawType)
        ? rawType
        : _guessMediaType(url);
    const out = { type, url };
    const text = _cleanString(raw.text || raw.caption || raw.title);
    const fileName = _cleanString(raw.fileName || raw.name);
    if (text) out.text = text;
    if (fileName) out.fileName = fileName;
    return out;
}

function _guessMediaType(url) {
    const clean = String(url || '').split('?')[0].toLowerCase();
    if (/\.(mp4|mov|m4v|webm|mkv|avi|3gp)$/.test(clean)) return 'video';
    if (/\.(mp3|wav|m4a|aac|ogg|oga)$/.test(clean)) return 'audio';
    if (/\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip)$/.test(clean)) return 'file';
    return 'image';
}

function _normalizeMediaList(raw) {
    const list = Array.isArray(raw) ? raw : (raw ? [raw] : []);
    return list.map(_normalizeMediaEntry).filter(Boolean).slice(0, 10);
}

function _splitPostMedia(media) {
    const normalized = _normalizeMediaList(media);
    const images = normalized.filter((m) => m.type === 'image').map((m) => m.url);
    const videos = normalized.filter((m) => m.type === 'video').map((m) => m.url);
    return {
        media: normalized.filter((m) => m.type === 'image' || m.type === 'video').map((m) => ({ type: m.type, url: m.url })),
        images,
        videos,
    };
}

function _poolMediaForCursor(cursor) {
    if (!CONTENT_AGENT_MEDIA_POOL.length) return [];
    const item = CONTENT_AGENT_MEDIA_POOL[Math.abs(Number(cursor) || 0) % CONTENT_AGENT_MEDIA_POOL.length];
    return _normalizeMediaList(item);
}

function _buildManualContent(body) {
    if (!body || typeof body !== 'object') return null;
    const text = _cleanString(body.text || body.message || body.caption);
    const media = _normalizeMediaList(body.media || body.medias || body.images || body.imageUrl || body.videoUrl);
    if (!text && media.length === 0) return null;
    return {
        category: _cleanString(body.category) || 'Communaut\u00e9',
        text,
        story: _cleanString(body.story || body.storyText) || text,
        media,
        source: _cleanString(body.source) || 'manual',
        sourceUrl: _cleanString(body.sourceUrl || body.url),
        sourceExternalId: _cleanString(body.sourceExternalId || body.externalId),
    };
}

function _importDocId(source, externalId) {
    return `${source}_${externalId}`.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 180);
}

function _facebookApiUrl() {
    const fields = [
        'id',
        'message',
        'story',
        'created_time',
        'permalink_url',
        'full_picture',
        'attachments{media,type,url,title,description}',
    ].join(',');
    const url = new URL(`https://graph.facebook.com/${FACEBOOK_GRAPH_VERSION}/${FACEBOOK_PAGE_ID}/posts`);
    url.searchParams.set('fields', fields);
    url.searchParams.set('limit', String(CONTENT_AGENT_FACEBOOK_LIMIT));
    url.searchParams.set('access_token', FACEBOOK_PAGE_ACCESS_TOKEN);
    return url.toString();
}

function _contentFromFacebookPost(post) {
    const message = _cleanString(post.message || post.story);
    if (!message) return null;
    const media = [];
    if (_cleanString(post.full_picture)) {
        media.push({ type: 'image', url: _cleanString(post.full_picture) });
    }
    const attachments = post.attachments && Array.isArray(post.attachments.data)
        ? post.attachments.data
        : [];
    for (const a of attachments) {
        const mediaUrl = _cleanString(a && a.media && a.media.image && a.media.image.src);
        if (mediaUrl) media.push({ type: 'image', url: mediaUrl });
    }
    const sourceUrl = _cleanString(post.permalink_url);
    const suffix = sourceUrl ? `\n\nSource Facebook: ${sourceUrl}` : '';
    return {
        category: 'Infos Officielles',
        text: `${message}${suffix}`.trim(),
        story: message,
        media,
        source: 'facebook',
        sourceUrl,
        sourceExternalId: _cleanString(post.id),
    };
}

async function findFreshFacebookContent() {
    if (!CONTENT_AGENT_FACEBOOK_ENABLED || !FACEBOOK_PAGE_ID || !FACEBOOK_PAGE_ACCESS_TOKEN) {
        return null;
    }
    const resp = await fetch(_facebookApiUrl());
    const raw = await resp.text();
    let payload = null;
    try { payload = JSON.parse(raw); } catch (_) {}
    if (!resp.ok) {
        throw new Error(`Facebook Graph API error ${resp.status}: ${raw.slice(0, 240)}`);
    }
    const posts = payload && Array.isArray(payload.data) ? payload.data : [];
    for (const post of posts) {
        const content = _contentFromFacebookPost(post);
        if (!content || !content.sourceExternalId) continue;
        const importId = _importDocId(content.source, content.sourceExternalId);
        const snap = await db.collection('content_agent_imports').doc(importId).get();
        if (!snap.exists) return content;
    }
    return null;
}

function _extractJsonObject(text) {
    const raw = _cleanString(text);
    if (!raw) return null;
    try {
        return JSON.parse(raw);
    } catch (_) {}
    const start = raw.indexOf('{');
    const end = raw.lastIndexOf('}');
    if (start === -1 || end === -1 || end <= start) return null;
    try {
        return JSON.parse(raw.slice(start, end + 1));
    } catch (_) {
        return null;
    }
}

async function loadRecentPostContext(limit = 8) {
    try {
        const snap = await db.collection('posts')
            .orderBy('createdAt', 'desc')
            .limit(limit)
            .get();
        return snap.docs.map((doc) => {
            const data = doc.data() || {};
            return {
                category: _cleanString(data.category),
                text: _cleanString(data.text).slice(0, 220),
                source: _cleanString(data.source),
            };
        }).filter((p) => p.text);
    } catch (e) {
        console.warn('Recent post context unavailable:', e.message);
        return [];
    }
}

async function callGeminiForJson(prompt) {
    if (!CONTENT_AGENT_GEMINI_ENABLED || !GEMINI_API_KEY) return null;
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${CONTENT_AGENT_GEMINI_MODEL}:generateContent`;
    const resp = await fetch(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': GEMINI_API_KEY,
        },
        body: JSON.stringify({
            contents: [
                {
                    role: 'user',
                    parts: [{ text: prompt }],
                },
            ],
            generationConfig: {
                temperature: 0.85,
                maxOutputTokens: 700,
                responseMimeType: 'application/json',
            },
        }),
    });
    const raw = await resp.text();
    let payload = null;
    try { payload = JSON.parse(raw); } catch (_) {}
    if (!resp.ok) {
        throw new Error(`Gemini API error ${resp.status}: ${raw.slice(0, 240)}`);
    }
    const parts = payload?.candidates?.[0]?.content?.parts || [];
    const text = parts.map((p) => p.text || '').join('\n').trim();
    return _extractJsonObject(text);
}

async function generateGeminiPostContent() {
    if (!CONTENT_AGENT_GEMINI_ENABLED || !GEMINI_API_KEY) return null;
    const recent = await loadRecentPostContext();
    const recentText = recent.length
        ? recent.map((p, i) => `${i + 1}. [${p.category || 'Sans categorie'}] ${p.text}`).join('\n')
        : 'Aucune publication recente disponible.';
    const prompt = [
        'Tu es Agent Konnect, un assistant communautaire pour Lualaba Konnect.',
        'Genere une publication courte, utile, naturelle et locale pour animer une communaute au Lualaba.',
        'Ne pretends jamais etre un humain. Ne donne pas de fausses actualites ni de chiffres inventes.',
        'Tu peux proposer une question, un conseil, une invitation a partager une information locale ou une astuce d usage de l application.',
        'Categories autorisees: Infos Officielles, Communaut\u00e9, Buzz, Alertes.',
        'Evite de repeter ces publications recentes:',
        recentText,
        'Retourne uniquement un JSON valide avec cette forme:',
        '{"category":"Communaut\u00e9","text":"texte du post","story":"version tres courte pour story"}',
        'Le champ text doit faire moins de 420 caracteres. Le champ story doit faire moins de 120 caracteres.',
    ].join('\n');

    const generated = await callGeminiForJson(prompt);
    if (!generated || typeof generated !== 'object') return null;
    const allowedCategories = new Set(['Infos Officielles', 'Communaut\u00e9', 'Buzz', 'Alertes']);
    const text = _cleanString(generated.text);
    if (!text) return null;
    const category = allowedCategories.has(_cleanString(generated.category))
        ? _cleanString(generated.category)
        : 'Communaut\u00e9';
    const story = _cleanString(generated.story) || text.slice(0, 120);
    return {
        category,
        text: text.slice(0, 700),
        story: story.slice(0, 180),
        media: _poolMediaForCursor(Date.now()),
        source: 'gemini',
        sourceExternalId: `gemini_${Date.now()}`,
    };
}

async function generateGeminiMessageText({ recipientCount = 1 } = {}) {
    if (!CONTENT_AGENT_GEMINI_ENABLED || !GEMINI_API_KEY) return '';
    const recent = await loadRecentPostContext(5);
    const recentText = recent.length
        ? recent.map((p, i) => `${i + 1}. [${p.category || 'Sans categorie'}] ${p.text}`).join('\n')
        : 'Aucune publication recente disponible.';
    const audience = Number(recipientCount) > 1
        ? `${recipientCount} utilisateurs, mais chacun le recevra comme un message individuel`
        : 'un utilisateur';
    const prompt = [
        'Tu es Agent Konnect, un assistant IA pour Lualaba Konnect.',
        `Genere un court message de chat naturel pour ${audience}.`,
        'Ne pretends jamais etre un humain. Ne donne pas de fausses actualites ni de chiffres inventes.',
        'Le message doit encourager une action utile: completer le profil, publier une info locale, consulter les nouveautes ou poser une question.',
        'Evite de repeter directement ces publications recentes:',
        recentText,
        'Retourne uniquement un JSON valide avec cette forme:',
        '{"text":"message de chat"}',
        'Le champ text doit faire moins de 240 caracteres.',
    ].join('\n');

    const generated = await callGeminiForJson(prompt);
    const text = _cleanString(generated && generated.text);
    return text ? text.slice(0, 320) : '';
}

function _agentNowMs() {
    return Date.now();
}

function _agentMinGapMs() {
    return CONTENT_AGENT_MIN_HOURS * 60 * 60 * 1000;
}

function _agentTimestamp(ms) {
    return admin.firestore.Timestamp.fromMillis(ms);
}

function _pickAgentContent(cursor) {
    const index = Math.abs(Number(cursor) || 0) % CONTENT_AGENT_POSTS.length;
    return { index, item: CONTENT_AGENT_POSTS[index] };
}

async function ensureContentAgentProfile() {
    const profileRef = db.collection('classic_users').doc(CONTENT_AGENT_AUTHOR_ID);
    const profileSnap = await profileRef.get();
    const payload = {
        uid: CONTENT_AGENT_AUTHOR_ID,
        firstName: CONTENT_AGENT_AUTHOR_NAME,
        displayName: CONTENT_AGENT_AUTHOR_NAME,
        photoUrl: CONTENT_AGENT_AUTHOR_AVATAR,
        publicStories: true,
        isCertified: true,
        isAutomated: true,
        accountType: 'system',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!profileSnap.exists) {
        payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }
    await profileRef.set(payload, { merge: true });
}

async function publishContentAgent({ force = false, reason = 'manual', contentOverride = null } = {}) {
    await ensureContentAgentProfile();

    const now = _agentNowMs();
    const stateRef = db.collection('system').doc('content_agent');
    let result = null;
    let facebookContent = null;
    let geminiContent = null;

    if (!contentOverride) {
        try {
            facebookContent = await findFreshFacebookContent();
        } catch (e) {
            console.error('Facebook content fetch error:', e.message);
        }

        if (!facebookContent) {
            try {
                geminiContent = await generateGeminiPostContent();
            } catch (e) {
                console.error('Gemini content generation error:', e.message);
            }
        }
    }

    await db.runTransaction(async (tx) => {
        const stateSnap = await tx.get(stateRef);
        const state = stateSnap.exists ? stateSnap.data() || {} : {};
        const lastPostAtMs = Number(state.lastPostAtMs || 0);
        const nextAllowedAtMs = lastPostAtMs + _agentMinGapMs();

        if (!force && lastPostAtMs > 0 && now < nextAllowedAtMs) {
            result = {
                ok: true,
                skipped: true,
                reason: 'too_soon',
                nextAllowedAtMs,
                minHours: CONTENT_AGENT_MIN_HOURS,
            };
            tx.set(stateRef, {
                lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
                lastRunAtMs: now,
                lastSkipReason: 'too_soon',
            }, { merge: true });
            return;
        }

        const cursor = Number(state.postCursor || 0);
        const picked = _pickAgentContent(cursor);
        const defaultContent = {
            category: picked.item.category,
            text: picked.item.text,
            story: picked.item.story || picked.item.text,
            media: _poolMediaForCursor(cursor),
            source: 'content_agent',
        };
        const content = contentOverride || facebookContent || geminiContent || defaultContent;
        const contentSource = _cleanString(content.source) || 'content_agent';
        const sourceExternalId = _cleanString(content.sourceExternalId);
        let importRef = null;

        if (sourceExternalId) {
            importRef = db.collection('content_agent_imports').doc(_importDocId(contentSource, sourceExternalId));
            const importSnap = await tx.get(importRef);
            if (importSnap.exists && !force) {
                result = {
                    ok: true,
                    skipped: true,
                    reason: 'already_imported',
                    source: contentSource,
                    sourceExternalId,
                };
                tx.set(stateRef, {
                    lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
                    lastRunAtMs: now,
                    lastSkipReason: 'already_imported',
                }, { merge: true });
                return;
            }
        }

        const postMedia = _splitPostMedia(content.media);
        const postRef = db.collection('posts').doc();
        const postPayload = {
            authorId: CONTENT_AGENT_AUTHOR_ID,
            authorName: CONTENT_AGENT_AUTHOR_NAME,
            authorAvatar: CONTENT_AGENT_AUTHOR_AVATAR,
            text: _cleanString(content.text),
            images: postMedia.images,
            videos: postMedia.videos,
            media: postMedia.media,
            category: _cleanString(content.category) || 'Communaut\u00e9',
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAtMs: now,
            likes: 0,
            likedBy: [],
            reactions: {},
            reactionsBy: {},
            commentsCount: 0,
            sharesCount: 0,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            mentions: [],
            isAutomated: true,
            source: contentSource,
        };
        if (_cleanString(content.sourceUrl)) postPayload.sourceUrl = _cleanString(content.sourceUrl);
        if (sourceExternalId) postPayload.sourceExternalId = sourceExternalId;

        tx.set(postRef, postPayload);

        let storyId = null;
        if (CONTENT_AGENT_CREATE_STORY) {
            const storyRef = db.collection('stories').doc();
            storyId = storyRef.id;
            const firstMedia = postMedia.media[0] || null;
            const storyPayload = {
                userId: CONTENT_AGENT_AUTHOR_ID,
                userName: CONTENT_AGENT_AUTHOR_NAME,
                text: _cleanString(content.story) || _cleanString(content.text),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAtMs: now,
                expiresAt: _agentTimestamp(now + 24 * 60 * 60 * 1000),
                isAutomated: true,
                source: contentSource,
            };
            if (firstMedia && firstMedia.type === 'image') storyPayload.imageUrl = firstMedia.url;
            if (firstMedia && firstMedia.type === 'video') storyPayload.videoUrl = firstMedia.url;
            tx.set(storyRef, storyPayload);
        }

        if (importRef) {
            tx.set(importRef, {
                source: contentSource,
                sourceExternalId,
                sourceUrl: _cleanString(content.sourceUrl),
                postId: postRef.id,
                storyId,
                importedAt: admin.firestore.FieldValue.serverTimestamp(),
                importedAtMs: now,
            }, { merge: true });
        }

        const nextCursor = (contentOverride || facebookContent || geminiContent) ? cursor : picked.index + 1;
        tx.set(stateRef, {
            enabled: CONTENT_AGENT_ENABLED,
            lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
            lastRunAtMs: now,
            lastPostAt: admin.firestore.FieldValue.serverTimestamp(),
            lastPostAtMs: now,
            lastPostId: postRef.id,
            lastStoryId: storyId,
            lastReason: reason,
            lastSkipReason: '',
            postCursor: nextCursor,
            minHours: CONTENT_AGENT_MIN_HOURS,
            intervalMinutes: CONTENT_AGENT_INTERVAL_MINUTES,
            lastSource: contentSource,
        }, { merge: true });

        result = {
            ok: true,
            skipped: false,
            postId: postRef.id,
            storyId,
            category: postPayload.category,
            authorId: CONTENT_AGENT_AUTHOR_ID,
            source: contentSource,
            mediaCount: postMedia.media.length,
            nextAllowedAtMs: now + _agentMinGapMs(),
        };
    });

    return result || { ok: false, error: 'agent_transaction_failed' };
}

function authorizeContentAgentRequest(req) {
    if (!CONTENT_AGENT_SECRET) {
        return { ok: false, status: 503, error: 'content_agent_secret_missing' };
    }

    const headerSecret = req.headers['x-agent-secret'];
    const bearer = (req.headers.authorization || '').startsWith('Bearer ')
        ? req.headers.authorization.split('Bearer ')[1]
        : '';
    const querySecret = req.query.secret;
    const provided = headerSecret || bearer || querySecret || '';

    if (provided !== CONTENT_AGENT_SECRET) {
        return { ok: false, status: 401, error: 'invalid_content_agent_secret' };
    }

    return { ok: true };
}

let contentAgentTimer = null;

function startContentAgentScheduler() {
    if (!CONTENT_AGENT_ENABLED) return;
    if (contentAgentTimer) return;

    const intervalMs = CONTENT_AGENT_INTERVAL_MINUTES * 60 * 1000;
    const run = (reason) => {
        publishContentAgent({ reason }).then((result) => {
            if (result.skipped) {
                console.log('Content agent skipped:', result.reason);
            } else {
                console.log('Content agent published:', result.postId);
            }
        }).catch((e) => {
            console.error('Content agent error:', e.message);
        });
    };

    setTimeout(() => run('startup'), 30000);
    contentAgentTimer = setInterval(() => run('interval'), intervalMs);
    console.log(`Content agent enabled. Interval=${CONTENT_AGENT_INTERVAL_MINUTES}min, minGap=${CONTENT_AGENT_MIN_HOURS}h`);
}

async function findUserProfile(uid) {
    const cleanUid = _cleanString(uid);
    if (!cleanUid) return null;
    for (const col of [...USER_COLLECTIONS, 'users']) {
        try {
            const snap = await db.collection(col).doc(cleanUid).get();
            if (!snap.exists) continue;
            return { uid: cleanUid, collection: col, data: snap.data() || {} };
        } catch (e) {}
    }
    return null;
}

async function loadRecipientUids({ recipients = [], allUsers = false, limit = 30 } = {}) {
    const max = Math.max(1, Math.min(CONTENT_AGENT_MESSAGE_MAX_RECIPIENTS, Number(limit) || 30));
    const out = [];
    const seen = new Set();
    const add = (uid) => {
        const clean = _cleanString(uid);
        if (!clean || clean === CONTENT_AGENT_AUTHOR_ID || seen.has(clean)) return;
        seen.add(clean);
        out.push(clean);
    };

    if (Array.isArray(recipients)) {
        recipients.forEach(add);
    } else {
        add(recipients);
    }

    if (allUsers && out.length < max) {
        for (const col of [...USER_COLLECTIONS, 'users']) {
            const snap = await db.collection(col).limit(max).get();
            snap.docs.forEach((doc) => add(doc.id));
            if (out.length >= max) break;
        }
    }

    return out.slice(0, max);
}

async function findOrCreateAgentChat(targetUid) {
    const targetProfile = await findUserProfile(targetUid);
    if (!targetProfile) {
        throw new Error(`recipient_not_found:${targetUid}`);
    }

    const existing = await db.collection('chats')
        .where('participants', 'array-contains', targetUid)
        .limit(100)
        .get();
    for (const doc of existing.docs) {
        const data = doc.data() || {};
        const participants = Array.isArray(data.participants)
            ? data.participants.map((p) => String(p))
            : [];
        if (participants.length === 2 && participants.includes(CONTENT_AGENT_AUTHOR_ID)) {
            return { chatRef: doc.ref, created: false, targetProfile };
        }
    }

    const chatRef = db.collection('chats').doc();
    await chatRef.set({
        participants: [CONTENT_AGENT_AUTHOR_ID, targetUid],
        lastMessage: '',
        lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
        unreadCounts: {
            [CONTENT_AGENT_AUTHOR_ID]: 0,
            [targetUid]: 0,
        },
        userTypes: {
            [CONTENT_AGENT_AUTHOR_ID]: 'classic_users',
            [targetUid]: targetProfile.collection,
        },
        typing: {
            [CONTENT_AGENT_AUTHOR_ID]: false,
            [targetUid]: false,
        },
        present: {
            [CONTENT_AGENT_AUTHOR_ID]: false,
            [targetUid]: false,
        },
        isAutomated: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { chatRef, created: true, targetProfile };
}

function _chatTextForMedia(media) {
    if (!media) return '';
    if (media.text) return media.text;
    if (media.type === 'video') return 'Video';
    if (media.type === 'audio') return 'Audio';
    if (media.type === 'file') return media.fileName || 'Fichier';
    return 'Photo';
}

function _buildAgentChatMessages({ text = '', media = [] } = {}) {
    const cleanText = _cleanString(text);
    const normalizedMedia = _normalizeMediaList(media);
    if (normalizedMedia.length === 0) {
        return cleanText ? [{ type: 'text', text: cleanText }] : [];
    }

    return normalizedMedia.map((item, index) => ({
        type: item.type,
        url: item.url,
        text: index === 0 && cleanText ? cleanText : _chatTextForMedia(item),
        ...(item.fileName ? { fileName: item.fileName } : {}),
    }));
}

async function sendAgentMessageToUser({ recipientUid, text = '', media = [] }) {
    await ensureContentAgentProfile();
    const { chatRef } = await findOrCreateAgentChat(recipientUid);
    const messages = _buildAgentChatMessages({ text, media });
    if (messages.length === 0) {
        throw new Error('empty_agent_message');
    }

    const batch = db.batch();
    for (const message of messages) {
        const msgRef = chatRef.collection('messages').doc();
        batch.set(msgRef, {
            senderId: CONTENT_AGENT_AUTHOR_ID,
            senderName: CONTENT_AGENT_AUTHOR_NAME,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
            delivered: false,
            deliveredAt: null,
            isAutomated: true,
            source: 'content_agent',
            ...message,
        });
    }

    const last = messages[messages.length - 1];
    const lastMessage = _cleanString(last.text) || _chatTextForMedia(last);
    batch.set(chatRef, {
        lastMessage,
        lastMessageTime: admin.firestore.FieldValue.serverTimestamp(),
        [`hiddenFor.${CONTENT_AGENT_AUTHOR_ID}`]: admin.firestore.FieldValue.delete(),
        [`hiddenFor.${recipientUid}`]: admin.firestore.FieldValue.delete(),
        [`unreadCounts.${recipientUid}`]: admin.firestore.FieldValue.increment(messages.length),
    }, { merge: true });

    await batch.commit();
    return { chatId: chatRef.id, messageCount: messages.length };
}

async function createAgentMessageJob({
    recipients,
    text = '',
    media = [],
    batchSize = CONTENT_AGENT_MESSAGE_BATCH_SIZE,
    intervalSeconds = CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS,
}) {
    await ensureContentAgentProfile();
    const cleanRecipients = Array.from(new Set((recipients || []).map(_cleanString).filter(Boolean)))
        .filter((uid) => uid !== CONTENT_AGENT_AUTHOR_ID);
    if (cleanRecipients.length === 0) {
        throw new Error('recipients_required');
    }

    const normalizedMedia = _normalizeMediaList(media);
    const jobRef = db.collection('content_agent_message_jobs').doc();
    const now = Date.now();
    const safeBatchSize = Math.max(1, Math.min(20, Number(batchSize) || CONTENT_AGENT_MESSAGE_BATCH_SIZE));
    const safeIntervalSeconds = Math.max(10, Number(intervalSeconds) || CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS);

    await jobRef.set({
        status: 'queued',
        authorId: CONTENT_AGENT_AUTHOR_ID,
        text: _cleanString(text),
        media: normalizedMedia,
        recipientCount: cleanRecipients.length,
        pendingCount: cleanRecipients.length,
        sentCount: 0,
        failedCount: 0,
        batchSize: safeBatchSize,
        intervalSeconds: safeIntervalSeconds,
        nextRunAtMs: now,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAtMs: now,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    for (let i = 0; i < cleanRecipients.length; i += 450) {
        const batch = db.batch();
        cleanRecipients.slice(i, i + 450).forEach((uid, index) => {
            batch.set(jobRef.collection('recipients').doc(uid), {
                uid,
                status: 'pending',
                order: i + index,
                attempts: 0,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
        await batch.commit();
    }

    return {
        jobId: jobRef.id,
        recipientCount: cleanRecipients.length,
        batchSize: safeBatchSize,
        intervalSeconds: safeIntervalSeconds,
    };
}

async function processAgentMessageJob(jobDoc) {
    const now = Date.now();
    const jobRef = jobDoc.ref;
    const job = jobDoc.data() || {};
    const nextRunAtMs = Number(job.nextRunAtMs || 0);
    if (nextRunAtMs > now) {
        return { jobId: jobRef.id, skipped: true, reason: 'waiting' };
    }

    const status = _cleanString(job.status);
    if (status !== 'queued' && status !== 'running') {
        return { jobId: jobRef.id, skipped: true, reason: 'inactive' };
    }

    const batchSize = Math.max(1, Math.min(20, Number(job.batchSize) || CONTENT_AGENT_MESSAGE_BATCH_SIZE));
    const intervalSeconds = Math.max(10, Number(job.intervalSeconds) || CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS);
    const recipientsSnap = await jobRef.collection('recipients')
        .where('status', '==', 'pending')
        .limit(batchSize)
        .get();

    if (recipientsSnap.empty) {
        await jobRef.set({
            status: 'completed',
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            completedAtMs: now,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { jobId: jobRef.id, completed: true, sent: 0, failed: 0 };
    }

    await jobRef.set({
        status: 'running',
        lockedAt: admin.firestore.FieldValue.serverTimestamp(),
        lockedAtMs: now,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    let sent = 0;
    let failed = 0;
    for (const recipientDoc of recipientsSnap.docs) {
        const data = recipientDoc.data() || {};
        const uid = _cleanString(data.uid || recipientDoc.id);
        try {
            const result = await sendAgentMessageToUser({
                recipientUid: uid,
                text: job.text || '',
                media: Array.isArray(job.media) ? job.media : [],
            });
            sent += 1;
            await recipientDoc.ref.set({
                status: 'sent',
                chatId: result.chatId,
                messageCount: result.messageCount,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
                sentAtMs: Date.now(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        } catch (e) {
            failed += 1;
            await recipientDoc.ref.set({
                status: 'failed',
                error: e.message,
                attempts: admin.firestore.FieldValue.increment(1),
                failedAt: admin.firestore.FieldValue.serverTimestamp(),
                failedAtMs: Date.now(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
    }

    const nextRun = Date.now() + intervalSeconds * 1000;
    await jobRef.set({
        pendingCount: admin.firestore.FieldValue.increment(-(sent + failed)),
        sentCount: admin.firestore.FieldValue.increment(sent),
        failedCount: admin.firestore.FieldValue.increment(failed),
        nextRunAtMs: nextRun,
        nextRunAt: admin.firestore.Timestamp.fromMillis(nextRun),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const fresh = await jobRef.get();
    const freshData = fresh.data() || {};
    if (Number(freshData.pendingCount || 0) <= 0) {
        await jobRef.set({
            status: 'completed',
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            completedAtMs: Date.now(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }

    return { jobId: jobRef.id, sent, failed, nextRunAtMs: nextRun };
}

let processingAgentMessageQueue = false;

async function processAgentMessageQueue() {
    if (processingAgentMessageQueue) return { skipped: true, reason: 'already_processing' };
    processingAgentMessageQueue = true;
    try {
        const queued = await db.collection('content_agent_message_jobs')
            .where('status', 'in', ['queued', 'running'])
            .limit(20)
            .get();
        const dueJobs = queued.docs
            .sort((a, b) => Number((a.data() || {}).nextRunAtMs || 0) - Number((b.data() || {}).nextRunAtMs || 0))
            .slice(0, 5);
        const results = [];
        for (const jobDoc of dueJobs) {
            results.push(await processAgentMessageJob(jobDoc));
        }
        return { ok: true, processed: results.length, results };
    } finally {
        processingAgentMessageQueue = false;
    }
}

let agentMessageQueueTimer = null;

function startAgentMessageQueueScheduler() {
    if (agentMessageQueueTimer) return;
    const tickMs = Math.max(10000, Math.min(60000, CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS * 1000));
    agentMessageQueueTimer = setInterval(() => {
        processAgentMessageQueue().catch((e) => {
            console.error('Content agent message queue error:', e.message);
        });
    }, tickMs);
    setTimeout(() => {
        processAgentMessageQueue().catch((e) => {
            console.error('Content agent message queue startup error:', e.message);
        });
    }, 10000);
    console.log(`Content agent message queue enabled. Batch=${CONTENT_AGENT_MESSAGE_BATCH_SIZE}, interval=${CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS}s`);
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

// --- ROUTE : AGENT DE CONTENU AUTONOME ---
app.all('/content-agent/run', async (req, res) => {
    const auth = authorizeContentAgentRequest(req);
    if (!auth.ok) return res.status(auth.status).json({ ok: false, error: auth.error });

    try {
        const force = req.query.force === '1' || (req.body && req.body.force === true);
        const manualContent = _buildManualContent(req.body);
        const result = await publishContentAgent({
            force,
            reason: 'manual_endpoint',
            contentOverride: manualContent,
        });
        return res.json(result);
    } catch (e) {
        console.error('Content agent endpoint error:', e.message);
        return res.status(500).json({ ok: false, error: 'content_agent_failed' });
    }
});

app.get('/content-agent/status', async (req, res) => {
    const auth = authorizeContentAgentRequest(req);
    if (!auth.ok) return res.status(auth.status).json({ ok: false, error: auth.error });

    try {
        const state = await db.collection('system').doc('content_agent').get();
        return res.json({
            ok: true,
            enabled: CONTENT_AGENT_ENABLED,
            authorId: CONTENT_AGENT_AUTHOR_ID,
            intervalMinutes: CONTENT_AGENT_INTERVAL_MINUTES,
            minHours: CONTENT_AGENT_MIN_HOURS,
            createStory: CONTENT_AGENT_CREATE_STORY,
            facebookEnabled: CONTENT_AGENT_FACEBOOK_ENABLED,
            facebookConfigured: Boolean(FACEBOOK_PAGE_ID && FACEBOOK_PAGE_ACCESS_TOKEN),
            geminiEnabled: CONTENT_AGENT_GEMINI_ENABLED,
            geminiConfigured: Boolean(GEMINI_API_KEY),
            geminiModel: CONTENT_AGENT_GEMINI_MODEL,
            mediaPoolCount: CONTENT_AGENT_MEDIA_POOL.length,
            messageBatchSize: CONTENT_AGENT_MESSAGE_BATCH_SIZE,
            messageIntervalSeconds: CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS,
            messageMaxRecipients: CONTENT_AGENT_MESSAGE_MAX_RECIPIENTS,
            messageTemplatesCount: CONTENT_AGENT_MESSAGE_TEMPLATES.length,
            state: state.exists ? state.data() : null,
        });
    } catch (e) {
        console.error('Content agent status error:', e.message);
        return res.status(500).json({ ok: false, error: 'content_agent_status_failed' });
    }
});

app.post('/content-agent/message', async (req, res) => {
    const auth = authorizeContentAgentRequest(req);
    if (!auth.ok) return res.status(auth.status).json({ ok: false, error: auth.error });

    try {
        const body = req.body || {};
        const requestedText = _cleanString(body.text || body.message);
        const media = _normalizeMediaList(body.media || body.medias || body.imageUrl || body.videoUrl || body.fileUrl);

        const recipients = await loadRecipientUids({
            recipients: body.recipients || body.recipientUid || body.uid,
            allUsers: body.allUsers === true,
            limit: body.limit || (body.allUsers === true ? CONTENT_AGENT_MESSAGE_MAX_RECIPIENTS : 30),
        });
        if (recipients.length === 0) {
            return res.status(400).json({ ok: false, error: 'recipients_required' });
        }
        let text = requestedText;
        let generatedBy = '';
        if (!text) {
            const generated = await buildAutonomousAgentMessage({ recipientCount: recipients.length });
            text = generated.text;
            generatedBy = generated.source;
        }

        const shouldQueue = body.allUsers === true ||
            body.stagger === true ||
            recipients.length > CONTENT_AGENT_MESSAGE_BATCH_SIZE;
        if (shouldQueue) {
            const job = await createAgentMessageJob({
                recipients,
                text,
                media,
                batchSize: body.batchSize || CONTENT_AGENT_MESSAGE_BATCH_SIZE,
                intervalSeconds: body.intervalSeconds || CONTENT_AGENT_MESSAGE_INTERVAL_SECONDS,
            });
            const firstBatch = await processAgentMessageQueue();
            return res.json({
                ok: true,
                queued: true,
                generatedText: requestedText.length === 0,
                generatedBy,
                messagePreview: text,
                ...job,
                firstBatch,
            });
        }

        const results = [];
        for (const uid of recipients) {
            try {
                const sent = await sendAgentMessageToUser({ recipientUid: uid, text, media });
                results.push({ uid, ok: true, ...sent });
            } catch (e) {
                results.push({ uid, ok: false, error: e.message });
            }
        }

        return res.json({
            ok: true,
            requested: recipients.length,
            sent: results.filter((r) => r.ok).length,
            failed: results.filter((r) => !r.ok).length,
            generatedText: requestedText.length === 0,
            generatedBy,
            messagePreview: text,
            results,
        });
    } catch (e) {
        console.error('Content agent message error:', e.message);
        return res.status(500).json({ ok: false, error: 'content_agent_message_failed' });
    }
});

// --- ROUTE : CONFIGURATION WEBRTC DYNAMIQUE (STUN + TURN) ---
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

        const rawNotificationType = data && data.type ? String(data.type) : '';
        const notificationType = rawNotificationType === 'alert' ? 'sos_alert' : rawNotificationType;
        const isCall = notificationType === 'incoming_call';
        const isSos = notificationType === 'sos_alert';
        const isUrgentAlert = isCall || isSos;

        const payload = {
            app_id: ONE_SIGNAL_APP_ID,
            ...(externalUserIds.length > 0 ? { include_external_user_ids: externalUserIds, channel_for_external_user_ids: "push" } : {}),
            ...(players.length > 0 ? { include_player_ids: players } : {}),
            headings: { fr: title || 'Lualaba Konnect', en: title || 'Lualaba Konnect' },
            contents: { fr: body || '', en: body || '' },
            large_icon: req.body.senderAvatarUrl || '', 
            big_picture: req.body.imageUrl || '',
            priority: 10,
            android_group: isCall ? "calls_group" : (isSos ? "sos_group" : "messages_group"),
            // For calls, keep TTL short so stale "incoming call" notifications don't arrive late.
            ttl: isCall ? 35 : (isSos ? 600 : 86400),
            buttons: isCall ? [
                { id: "accept", text: "Répondre", icon: "ic_menu_call" },
                { id: "decline", text: "Refuser", icon: "ic_menu_close" }
            ] : (isSos ? [
                { id: "open_sos", text: "Ouvrir" }
            ] : []),
            data: { ...data, type: notificationType, sentBy: caller.uid }
        };

        // Only set android_channel_id if you provided real channel UUIDs from OneSignal dashboard.
        // Passing an unknown value can cause confusing behavior on some devices.
        const channelId = isUrgentAlert ? ONESIGNAL_ANDROID_CHANNEL_CALLS : ONESIGNAL_ANDROID_CHANNEL_MESSAGES;
        if (channelId && typeof channelId === 'string' && channelId.trim().length > 0) {
            payload.android_channel_id = channelId.trim();
        }

        // Optional call sounds (recommended to configure on the OneSignal "Calls" channel instead).
        if (isUrgentAlert) {
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
app.listen(port, () => {
    console.log('Server Live on port', port);
    startContentAgentScheduler();
    startAgentMessageQueueScheduler();
});
