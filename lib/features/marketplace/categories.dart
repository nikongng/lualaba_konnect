class Categories {
  static const Map<String, List<String>> map = {
    'Tout': [],
    'Véhicules': [],
    'Immobilier': ['Ventes immobilières', 'Locations'],
    'Maison et jardin': ['Meubles', 'Décoration', 'Électroménager', 'Outils', 'Bricolage'],
    'Électronique': ['Électroniques et ordinateurs', 'Téléphones mobiles'],
    'Mode et style': ['Vêtements', 'Beauté', 'Chaussures', 'Sacs', 'Bijoux', 'Connaissance'],
    'Famille': ['Outils pour enfants', 'Santé'],
    'Divertissement': ['Jeu vidéo', 'Livres', 'Films et musique'],
  };

  static List<String> mainCategories() => map.keys.toList();
  static List<String> subCategories(String main) => map[main] ?? [];
}
