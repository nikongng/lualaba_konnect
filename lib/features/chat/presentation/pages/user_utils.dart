class UserUtils {
  static String formatName(Map<String, dynamic>? data) {
    if (data == null) return "Utilisateur";

    // 1. Test des combinaisons Prénom + Nom
    final firstKeys = ['firstName', 'firstname', 'prenom', 'givenName'];
    final lastKeys = ['lastName', 'lastname', 'nom', 'familyName'];

    String? first;
    String? last;

    for (var k in firstKeys) {
      if (data[k]?.toString().trim().isNotEmpty == true) {
        first = data[k].toString().trim();
        break;
      }
    }
    for (var k in lastKeys) {
      if (data[k]?.toString().trim().isNotEmpty == true) {
        last = data[k].toString().trim();
        break;
      }
    }

    if (first != null && last != null) return "$first $last";
    if (first != null) return first;

    // 2. Fallback sur les noms complets
    final fullKeys = ['displayName', 'name', 'fullName', 'fullname'];
    for (var k in fullKeys) {
      if (data[k]?.toString().trim().isNotEmpty == true) {
        return data[k].toString().trim();
      }
    }

    return "Utilisateur";
  }
}