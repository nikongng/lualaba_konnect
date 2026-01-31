/**
 * Script de migration pour Firestore :
 * - Ajoute `categoryMain` et `categorySub` aux documents de `market_products`.
 * Usage :
 *   node migrate_categories.js
 * Assure-toi que le fichier de service account présent dans ce dossier est correct
 * (lualaba-konnect-firebase-adminsdk-fbsvc-efe520ce27.json).
 */

const admin = require('firebase-admin');
const path = require('path');

const serviceAccount = require('./lualaba-konnect-firebase-adminsdk-fbsvc-efe520ce27.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const Categories = {
  'Tout': [],
  'Véhicules': [],
  'Immobilier': ['Ventes immobilières', 'Locations'],
  'Maison et jardin': ['Meubles', 'Décoration', 'Électroménager', 'Outils', 'Bricolage'],
  'Électronique': ['Électroniques et ordinateurs', 'Téléphones mobiles'],
  'Mode et style': ['Vêtements', 'Beauté', 'Chaussures', 'Sacs', 'Bijoux', 'Connaissance'],
  'Famille': ['Outils pour enfants', 'Santé'],
  'Divertissement': ['Jeu vidéo', 'Livres', 'Films et musique'],
};

function findCategoryFields(cat) {
  if (!cat || typeof cat !== 'string') return { main: null, sub: null };
  const c = cat.trim().toLowerCase();
  for (const main of Object.keys(Categories)) {
    if (main.toLowerCase() === c) return { main, sub: null };
    const subs = Categories[main] || [];
    for (const s of subs) {
      if (s.toLowerCase() === c) return { main, sub: s };
    }
  }
  return { main: null, sub: null };
}

async function migrate() {
  console.log('Début de la migration des catégories...');
  const snapshot = await db.collection('market_products').get();
  console.log(`Documents trouvés: ${snapshot.size}`);

  let batch = db.batch();
  let ops = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const cat = data.category || '';
    const { main, sub } = findCategoryFields(cat);
    const update = {};
    if (main) update.categoryMain = main;
    if (sub) update.categorySub = sub;
    // If no matching main/sub found, leave fields unset.
    if (Object.keys(update).length > 0) {
      batch.update(doc.ref, update);
      ops++;
    }

    if (ops >= 450) {
      await batch.commit();
      console.log('Batch commit');
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();
  console.log('Migration terminée.');
}

migrate().catch(err => {
  console.error('Erreur migration:', err);
  process.exit(1);
});
