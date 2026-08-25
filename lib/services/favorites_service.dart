import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _favoritesKey = 'favorite_cities';
  static const String _recentKey = 'recent_cities';

  Future<List<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getStringList(_favoritesKey) ?? [];
  }

  Future<bool> isFavorite(String city) async {
    final favorites = await getFavorites();

    return favorites.any(
          (item) => item.toLowerCase() == city.toLowerCase(),
    );
  }

  Future<void> addFavorite(String city) async {
    final prefs = await SharedPreferences.getInstance();

    final favorites = await getFavorites();

    final exists = favorites.any(
          (item) => item.toLowerCase() == city.toLowerCase(),
    );

    if (!exists) {
      favorites.add(city);

      await prefs.setStringList(
        _favoritesKey,
        favorites,
      );
    }
  }

  Future<void> removeFavorite(String city) async {
    final prefs = await SharedPreferences.getInstance();

    final favorites = await getFavorites();

    favorites.removeWhere(
          (item) => item.toLowerCase() == city.toLowerCase(),
    );

    await prefs.setStringList(
      _favoritesKey,
      favorites,
    );
  }

  Future<void> addRecent(String city) async {
    final prefs = await SharedPreferences.getInstance();

    final recent = await getRecent();

    recent.removeWhere(
          (item) => item.toLowerCase() == city.toLowerCase(),
    );

    recent.insert(0, city);

    // Keep only the latest 5 searches.
    if (recent.length > 5) {
      recent.removeRange(5, recent.length);
    }

    await prefs.setStringList(
      _recentKey,
      recent,
    );
  }

  Future<List<String>> getRecent() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getStringList(_recentKey) ?? [];
  }

  Future<void> removeRecent(String city) async {
    final prefs = await SharedPreferences.getInstance();

    final recent = await getRecent();

    recent.removeWhere(
          (item) => item.toLowerCase() == city.toLowerCase(),
    );

    await prefs.setStringList(
      _recentKey,
      recent,
    );
  }

  Future<void> clearRecent() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_recentKey);
  }
}