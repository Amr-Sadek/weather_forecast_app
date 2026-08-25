import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import 'package:weather_icons/weather_icons.dart';
import '../models/forecast_model.dart';
import '../models/weather_model.dart';
import '../services/favorites_service.dart';
import '../services/weather_service.dart';
import '../widgets/temperature_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WeatherService _weatherService = WeatherService();
  final FavoritesService _favoritesService = FavoritesService();

  WeatherModel? _weather;
  List<ForecastModel> _forecast = [];

  bool _isLoading = true;
  String? _errorMessage;

  List<String> _favorites = [];
  List<String> _recentCities = [];

  bool _isFavorite = false;

  // Location shown in the header.
  // GPS location uses reverse geocoding so the app can show
  // the most specific available locality instead of only the
  // city returned by the weather API.
  String _locationName = 'Current Location';
  String _locationSubtitle = '';

  @override
  void initState() {
    super.initState();

    _loadSavedCities();
    _loadWeatherFromLocation();
  }

  // ===========================================================================
  // SAVED CITIES
  // ===========================================================================

  Future<void> _loadSavedCities() async {
    final favorites = await _favoritesService.getFavorites();
    final recent = await _favoritesService.getRecent();

    if (!mounted) return;

    setState(() {
      _favorites = favorites;
      _recentCities = recent;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_weather == null) return;

    final city = _weather!.cityName;

    if (_isFavorite) {
      await _favoritesService.removeFavorite(city);
    } else {
      await _favoritesService.addFavorite(city);
    }

    final favorites = await _favoritesService.getFavorites();

    if (!mounted) return;

    setState(() {
      _isFavorite = !_isFavorite;
      _favorites = favorites;
    });
  }

  Future<void> _removeFavorite(String city) async {
    await _favoritesService.removeFavorite(city);

    if (!mounted) return;

    setState(() {
      _favorites.removeWhere(
        (item) => item.toLowerCase() == city.toLowerCase(),
      );

      if (_weather != null &&
          _weather!.cityName.toLowerCase() == city.toLowerCase()) {
        _isFavorite = false;
      }
    });
  }

  Future<void> _removeRecent(String city) async {
    await _favoritesService.removeRecent(city);

    final recent = await _favoritesService.getRecent();

    if (!mounted) return;

    setState(() {
      _recentCities = recent;
    });
  }

  Future<void> _openSavedCity(String city) async {
    Navigator.of(context).pop();
    await _searchCity(city);
  }

  // ===========================================================================
  // SEARCH SHEET
  // ===========================================================================

  void _showSearchScreen() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        return _SearchSheet(
          favorites: List<String>.from(_favorites),
          recentCities: List<String>.from(_recentCities),
          onSearch: (city) async {
            Navigator.of(sheetContext).pop();
            await _searchCity(city);
          },
          onCitySelected: (city) async {
            Navigator.of(sheetContext).pop();
            await _searchCity(city);
          },
          onRecentRemoved: _removeRecent,
        );
      },
    );
  }

  void _showSavedCities() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF102A43),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) {
        return _SavedCitiesSheet(
          favorites: _favorites,
          recentCities: _recentCities,
          onCitySelected: _openSavedCity,
          onFavoriteRemoved: _removeFavorite,
          onRecentRemoved: _removeRecent,
        );
      },
    );
  }

  // ===========================================================================
  // LOCATION
  // ===========================================================================

  Future<Position> _getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _loadLocationName({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&localityLanguage=en',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final locality =
          (data['locality'] ??
                  data['city'] ??
                  data['localityInfo']?['administrative']?[0]?['name'])
              ?.toString()
              .trim();

      final city = data['city']?.toString().trim();
      final subdivision = data['principalSubdivision']?.toString().trim();

      if (!mounted) return;

      setState(() {
        if (locality != null && locality.isNotEmpty) {
          _locationName = locality;
        }

        if (city != null &&
            city.isNotEmpty &&
            city.toLowerCase() != locality?.toLowerCase()) {
          _locationSubtitle = city;
        } else if (subdivision != null &&
            subdivision.isNotEmpty &&
            subdivision.toLowerCase() != locality?.toLowerCase()) {
          _locationSubtitle = subdivision;
        } else {
          _locationSubtitle = '';
        }
      });
    } catch (_) {
      // Weather loading should continue even if reverse geocoding fails.
    }
  }

  Future<void> _loadWeatherFromLocation() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final position = await _getCurrentPosition();

      await _loadLocationName(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final results = await Future.wait([
        _weatherService.getCurrentWeather(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
        _weatherService.getForecast(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      ]);

      final weather = results[0] as WeatherModel;
      final forecast = results[1] as List<ForecastModel>;

      final favorite = await _favoritesService.isFavorite(weather.cityName);

      if (!mounted) return;

      setState(() {
        _weather = weather;
        _forecast = forecast;
        _isFavorite = favorite;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _cleanErrorMessage(e);
      });
    }
  }

  // ===========================================================================
  // SEARCH CITY
  // ===========================================================================

  Future<void> _searchCity(String city) async {
    final trimmedCity = city.trim();

    if (trimmedCity.isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _weatherService.getWeatherByCity(trimmedCity),
        _weatherService.getForecastByCity(trimmedCity),
      ]);

      final weather = results[0] as WeatherModel;
      final forecast = results[1] as List<ForecastModel>;

      await _favoritesService.addRecent(weather.cityName);

      final favorite = await _favoritesService.isFavorite(weather.cityName);

      final recent = await _favoritesService.getRecent();

      if (!mounted) return;

      setState(() {
        _weather = weather;
        _forecast = forecast;
        _isFavorite = favorite;
        _recentCities = recent;
        _locationName = weather.cityName;
        _locationSubtitle = weather.country;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;

        if (e.toString().contains('City not found')) {
          _errorMessage = 'We couldn\'t find "$trimmedCity".';
        } else {
          _errorMessage = 'Something went wrong.\nPlease try again.';
        }
      });
    }
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString();

    if (message.contains('Location services are disabled')) {
      return 'Location services are disabled.\n'
          'Please enable location and try again.';
    }

    if (message.contains('Location permission denied')) {
      return 'Location permission was denied.\n'
          'Please allow location access to continue.';
    }

    if (message.contains('permanently denied')) {
      return 'Location permission is permanently denied.\n'
          'Please enable it from app settings.';
    }

    return 'Unable to load weather data.\n'
        'Please try again.';
  }

  // ===========================================================================
  // WEATHER BACKGROUND
  // ===========================================================================

  bool _isNight() {
    if (_weather == null) {
      return false;
    }

    final now = DateTime.now();

    return now.isBefore(_weather!.sunrise) || now.isAfter(_weather!.sunset);
  }

  Color _backgroundTop() {
    if (_weather == null) return const Color(0xFF2E86C1);

    final code = _weather!.icon.trim().toLowerCase();

    if (code == '01d') return const Color(0xFF42A5F5);
    if (code == '01n') return const Color(0xFF172554);

    if (code.startsWith('02')) {
      return _isNight() ? const Color(0xFF263A59) : const Color(0xFF6D8EAA);
    }

    if (code.startsWith('03') || code.startsWith('04')) {
      return _isNight() ? const Color(0xFF263447) : const Color(0xFF7892A6);
    }

    if (code.startsWith('09') || code.startsWith('10')) {
      return const Color(0xFF376B8F);
    }

    if (code.startsWith('11')) return const Color(0xFF574B87);
    if (code.startsWith('13')) return const Color(0xFF5E8DA8);
    if (code.startsWith('50')) return const Color(0xFF617482);

    return const Color(0xFF286C9E);
  }

  Color _backgroundBottom() {
    if (_weather == null) return const Color(0xFF071A2E);

    final code = _weather!.icon.trim().toLowerCase();

    if (code == '01d') return const Color(0xFF0B2744);
    if (code == '01n') return const Color(0xFF050816);

    if (code.startsWith('02')) {
      return _isNight() ? const Color(0xFF0D1729) : const Color(0xFF20394F);
    }

    if (code.startsWith('03') || code.startsWith('04')) {
      return _isNight() ? const Color(0xFF0B1423) : const Color(0xFF1E3242);
    }

    if (code.startsWith('09') || code.startsWith('10')) {
      return const Color(0xFF0A1D2E);
    }

    if (code.startsWith('11')) return const Color(0xFF100D24);
    if (code.startsWith('13')) return const Color(0xFF173446);
    if (code.startsWith('50')) return const Color(0xFF17252F);

    return const Color(0xFF092C4A);
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  IconData _weatherIconData(String iconCode) {
    switch (iconCode.trim().toLowerCase()) {
      case '01d':
        return WeatherIcons.day_sunny;
      case '01n':
        return WeatherIcons.night_clear;
      case '02d':
        return WeatherIcons.day_cloudy;
      case '02n':
        return WeatherIcons.night_alt_cloudy;
      case '03d':
      case '03n':
      case '04d':
      case '04n':
        return WeatherIcons.cloudy;
      case '09d':
      case '09n':
        return WeatherIcons.showers;
      case '10d':
        return WeatherIcons.day_rain;
      case '10n':
        return WeatherIcons.night_alt_rain;
      case '11d':
        return WeatherIcons.day_thunderstorm;
      case '11n':
        return WeatherIcons.night_alt_thunderstorm;
      case '13d':
        return WeatherIcons.day_snow;
      case '13n':
        return WeatherIcons.night_alt_snow;
      case '50d':
        return WeatherIcons.day_fog;
      case '50n':
        return WeatherIcons.night_fog;
      default:
        return WeatherIcons.cloudy;
    }
  }

  Color _weatherIconColor(String iconCode) {
    final code = iconCode.trim().toLowerCase();

    if (code == '01d') return const Color(0xFFFFD54F);
    if (code == '01n') return const Color(0xFFE8EEFF);
    if (code.startsWith('02')) return const Color(0xFFFFE082);
    if (code.startsWith('03') || code.startsWith('04')) {
      return const Color(0xFFE8EEF5);
    }
    if (code.startsWith('09') || code.startsWith('10')) {
      return const Color(0xFF8FD3FF);
    }
    if (code.startsWith('11')) return const Color(0xFFFFD54F);
    if (code.startsWith('13')) return const Color(0xFFDDF5FF);
    if (code.startsWith('50')) return const Color(0xFFD5DEE6);

    return Colors.white;
  }

  Widget _weatherIcon(String iconCode, {double size = 60}) {
    return BoxedIcon(
      _weatherIconData(iconCode),
      size: size,
      color: _weatherIconColor(iconCode),
    );
  }

  String _formatHour(DateTime dateTime) {
    return DateFormat('h a').format(dateTime);
  }

  String _formatDay(DateTime dateTime) {
    return DateFormat('EEE').format(dateTime);
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value[0].toUpperCase() + value.substring(1);
  }

  List<ForecastModel> _hourlyForecast() {
    if (_forecast.isEmpty) {
      return [];
    }

    return _forecast.take(8).toList();
  }

  double _todayMinTemperature() {
    if (_weather == null) {
      return 0;
    }

    if (_forecast.isEmpty) {
      return _weather!.minTemperature;
    }

    final now = DateTime.now();

    final today = _forecast.where((item) {
      return item.dateTime.year == now.year &&
          item.dateTime.month == now.month &&
          item.dateTime.day == now.day;
    }).toList();

    if (today.isEmpty) {
      return _weather!.minTemperature;
    }

    return today
        .map((item) => item.minTemperature)
        .reduce((a, b) => a < b ? a : b);
  }

  double _todayMaxTemperature() {
    if (_weather == null) {
      return 0;
    }

    if (_forecast.isEmpty) {
      return _weather!.maxTemperature;
    }

    final now = DateTime.now();

    final today = _forecast.where((item) {
      return item.dateTime.year == now.year &&
          item.dateTime.month == now.month &&
          item.dateTime.day == now.day;
    }).toList();

    if (today.isEmpty) {
      return _weather!.maxTemperature;
    }

    return today
        .map((item) => item.maxTemperature)
        .reduce((a, b) => a > b ? a : b);
  }

  List<_DailyWeather> _dailyForecast() {
    if (_forecast.isEmpty) {
      return [];
    }

    final Map<String, List<ForecastModel>> grouped = {};

    for (final item in _forecast) {
      final key = DateFormat('yyyy-MM-dd').format(item.dateTime);

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }

    final List<_DailyWeather> result = [];

    for (final entry in grouped.entries.take(5)) {
      final items = entry.value;

      double minTemp = items.first.minTemperature;
      double maxTemp = items.first.maxTemperature;

      ForecastModel representative = items.first;
      int bestNoonDistance = (items.first.dateTime.hour - 12).abs();

      for (final item in items) {
        if (item.minTemperature < minTemp) {
          minTemp = item.minTemperature;
        }

        if (item.maxTemperature > maxTemp) {
          maxTemp = item.maxTemperature;
        }

        final noonDistance = (item.dateTime.hour - 12).abs();

        if (noonDistance < bestNoonDistance) {
          bestNoonDistance = noonDistance;
          representative = item;
        }
      }

      result.add(
        _DailyWeather(
          dateTime: representative.dateTime,
          minTemperature: minTemp,
          maxTemperature: maxTemp,
          condition: representative.condition,
          icon: representative.icon,
        ),
      );
    }

    return result;
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_backgroundTop(), _backgroundBottom()],
          ),
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _weather == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_weather == null) {
      return _buildErrorState();
    }

    return Stack(
      children: [
        RefreshIndicator(
          color: Colors.white,
          backgroundColor: const Color(0xFF164B70),
          onRefresh: _loadWeatherFromLocation,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 35),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeader(),

                    const SizedBox(height: 28),

                    _buildCurrentWeather(),

                    const SizedBox(height: 30),

                    _buildHourlySection(),

                    const SizedBox(height: 16),

                    TemperatureChart(forecast: _forecast),

                    const SizedBox(height: 30),

                    _buildDetailsSection(),

                    const SizedBox(height: 30),

                    _buildDailySection(),

                    const SizedBox(height: 10),
                  ]),
                ),
              ),
            ],
          ),
        ),

        if (_errorMessage != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: _buildErrorBanner(),
          ),

        if (_isLoading && _weather != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),

                  const SizedBox(width: 9),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _locationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          _locationSubtitle.isNotEmpty
                              ? _locationSubtitle
                              : _weather!.country,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerActionButton(
                  icon: _isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  tooltip: _isFavorite ? 'Remove favorite' : 'Add favorite',
                  onPressed: _toggleFavorite,
                  active: _isFavorite,
                ),

                const SizedBox(width: 7),

                _headerActionButton(
                  icon: Icons.bookmarks_rounded,
                  tooltip: 'Saved cities',
                  onPressed: _showSavedCities,
                ),

                const SizedBox(width: 7),

                _headerActionButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Use my location',
                  onPressed: _isLoading ? null : _loadWeatherFromLocation,
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 8),

        Text(
          DateFormat('EEEE, MMMM d').format(DateTime.now()),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 18),

        _buildSearchBar(),
      ],
    );
  }

  Widget _headerActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: active
            ? const Color(0x33FFD166)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? const Color(0x55FFD166)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: active ? const Color(0xFFFFD166) : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: _showSearchScreen,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.65),
              size: 22,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Text(
                'Search for a city...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14,
                ),
              ),
            ),

            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.35),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CURRENT WEATHER
  // ===========================================================================

  Widget _buildCurrentWeather() {
    return Column(
      children: [
        Text(
          'CURRENT WEATHER',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),

        const SizedBox(height: 6),

        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.75, end: 1.0),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: _weatherIcon(_weather!.icon, size: 132),
        ),

        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _weather!.temperature),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.round().toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 86,
                    height: 0.9,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -5,
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '°',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 8),

        Text(
          _capitalize(_weather!.description),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 6),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.thermostat_rounded,
              color: Colors.white.withValues(alpha: 0.55),
              size: 16,
            ),

            const SizedBox(width: 5),

            Text(
              'Feels like ${_weather!.feelsLike.round()}°',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 14,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 16,
              ),

              const SizedBox(width: 4),

              Text(
                '${_todayMaxTemperature().round()}°',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(width: 12),

              Container(
                width: 1,
                height: 15,
                color: Colors.white.withValues(alpha: 0.18),
              ),

              const SizedBox(width: 12),

              const Icon(
                Icons.arrow_downward_rounded,
                color: Colors.white70,
                size: 16,
              ),

              const SizedBox(width: 4),

              Text(
                '${_todayMinTemperature().round()}°',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // HOURLY FORECAST
  // ===========================================================================

  Widget _buildHourlySection() {
    final hourly = _hourlyForecast();

    return _glassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hourly Forecast',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              Text(
                'Next 24h',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 11,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          SizedBox(
            height: 138,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: hourly.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = hourly[index];
                final isNow = index == 0;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 82,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: isNow
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.20),
                              Colors.white.withValues(alpha: 0.08),
                            ],
                          )
                        : null,
                    color: isNow ? null : Colors.white.withValues(alpha: 0.045),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isNow
                          ? Colors.white.withValues(alpha: 0.20)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isNow ? 'Now' : _formatHour(item.dateTime),
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: isNow ? 0.95 : 0.55,
                          ),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      _weatherIcon(item.icon, size: 43),

                      Text(
                        '${item.temperature.round()}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DETAILS
  // ===========================================================================

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          title: 'Today\'s Details',
          icon: Icons.analytics_outlined,
        ),

        const SizedBox(height: 14),

        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            _statCard(
              icon: Icons.water_drop_rounded,
              title: 'Humidity',
              value: '${_weather!.humidity}%',
            ),

            _statCard(
              icon: Icons.air_rounded,
              title: 'Wind',
              value: '${_weather!.windSpeed.toStringAsFixed(1)} m/s',
            ),

            _statCard(
              icon: Icons.thermostat_rounded,
              title: 'Min / Max',
              value:
                  '${_todayMinTemperature().round()}° / '
                  '${_todayMaxTemperature().round()}°',
            ),

            _statCard(
              icon: Icons.speed_rounded,
              title: 'Pressure',
              value: '${_weather!.pressure} hPa',
            ),

            _statCard(
              icon: Icons.visibility_rounded,
              title: 'Visibility',
              value: '${(_weather!.visibility / 1000).toStringAsFixed(1)} km',
            ),

            _statCard(
              icon: Icons.cloud_rounded,
              title: 'Cloudiness',
              value: '${_weather!.clouds}%',
            ),
          ],
        ),

        const SizedBox(height: 12),

        _sunCard(),
      ],
    );
  }

  Widget _sunCard() {
    final sunrise = DateFormat('h:mm a').format(_weather!.sunrise);

    final sunset = DateFormat('h:mm a').format(_weather!.sunset);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wb_twilight_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),

              const SizedBox(width: 10),

              const Text(
                'Sunrise & Sunset',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _sunTime(
                  icon: Icons.wb_sunny_rounded,
                  title: 'Sunrise',
                  time: sunrise,
                ),
              ),

              Container(
                width: 1,
                height: 50,
                color: Colors.white.withValues(alpha: 0.10),
              ),

              Expanded(
                child: _sunTime(
                  icon: Icons.nightlight_round,
                  title: 'Sunset',
                  time: sunset,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sunTime({
    required IconData icon,
    required String title,
    required String time,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 27),

        const SizedBox(width: 10),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.50),
                fontSize: 11,
              ),
            ),

            const SizedBox(height: 3),

            Text(
              time,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 5 DAY FORECAST
  // ===========================================================================

  Widget _buildDailySection() {
    final daily = _dailyForecast();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          title: '5-Day Forecast',
          icon: Icons.calendar_month_rounded,
        ),

        const SizedBox(height: 14),

        _glassContainer(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < daily.length; i++) ...[
                _dailyRow(item: daily[i], isFirst: i == 0),

                if (i != daily.length - 1)
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _dailyRow({required _DailyWeather item, required bool isFirst}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          SizedBox(
            width: 65,
            child: Text(
              isFirst ? 'Today' : _formatDay(item.dateTime),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          _weatherIcon(item.icon, size: 42),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              _capitalize(item.condition),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 13,
              ),
            ),
          ),

          Text(
            '${item.maxTemperature.round()}°',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(width: 12),

          Text(
            '${item.minTemperature.round()}°',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // UI HELPERS
  // ===========================================================================

  Widget _sectionTitle({required String title, required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.75), size: 18),

        const SizedBox(width: 8),

        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _glassContainer({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }

  // ===========================================================================
  // ERROR STATES
  // ===========================================================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Colors.white,
                size: 46,
              ),
            ),

            const SizedBox(height: 22),

            const Text(
              'Weather unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              _errorMessage ?? 'We couldn\'t load the latest weather data.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _loadWeatherFromLocation,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Use My Location'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF164B70),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF111827).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),

            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
              },
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DAILY WEATHER MODEL
// =============================================================================

class _DailyWeather {
  final DateTime dateTime;
  final double minTemperature;
  final double maxTemperature;
  final String condition;
  final String icon;

  const _DailyWeather({
    required this.dateTime,
    required this.minTemperature,
    required this.maxTemperature,
    required this.condition,
    required this.icon,
  });
}

// =============================================================================
// SAVED CITIES SHEET
// =============================================================================

class _SavedCitiesSheet extends StatelessWidget {
  final List<String> favorites;
  final List<String> recentCities;

  final Future<void> Function(String city) onCitySelected;
  final Future<void> Function(String city) onFavoriteRemoved;
  final Future<void> Function(String city) onRecentRemoved;

  const _SavedCitiesSheet({
    required this.favorites,
    required this.recentCities,
    required this.onCitySelected,
    required this.onFavoriteRemoved,
    required this.onRecentRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = favorites.isNotEmpty || recentCities.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                'Saved Cities',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 20),

              if (!hasContent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 42),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.location_city_rounded,
                          color: Colors.white.withValues(alpha: 0.28),
                          size: 54,
                        ),

                        const SizedBox(height: 14),

                        Text(
                          'No saved cities yet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 14,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          'Search for a city and save it with ★',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (favorites.isNotEmpty) ...[
                        _sheetTitle(Icons.star_rounded, 'Favorites'),

                        const SizedBox(height: 9),

                        ...favorites.map(
                          (city) => _cityTile(
                            city: city,
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFFFD166),
                            onTap: () => onCitySelected(city),
                            onDelete: () => onFavoriteRemoved(city),
                          ),
                        ),
                      ],

                      if (recentCities.isNotEmpty) ...[
                        if (favorites.isNotEmpty) const SizedBox(height: 15),

                        _sheetTitle(Icons.history_rounded, 'Recent Searches'),

                        const SizedBox(height: 9),

                        ...recentCities.map(
                          (city) => _cityTile(
                            city: city,
                            icon: Icons.history_rounded,
                            iconColor: Colors.white.withValues(alpha: 0.55),
                            onTap: () => onCitySelected(city),
                            onDelete: () => onRecentRemoved(city),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.75), size: 18),

        const SizedBox(width: 8),

        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _cityTile({
    required String city,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        title: Text(
          city,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Tap to view weather',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
          ),
        ),
        trailing: IconButton(
          tooltip: 'Remove',
          onPressed: onDelete,
          icon: Icon(
            Icons.close_rounded,
            color: Colors.white.withValues(alpha: 0.38),
            size: 19,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SEARCH SHEET
// =============================================================================

class _SearchSheet extends StatefulWidget {
  final List<String> favorites;
  final List<String> recentCities;

  final Future<void> Function(String city) onSearch;
  final Future<void> Function(String city) onCitySelected;
  final Future<void> Function(String city) onRecentRemoved;

  const _SearchSheet({
    required this.favorites,
    required this.recentCities,
    required this.onSearch,
    required this.onCitySelected,
    required this.onRecentRemoved,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final TextEditingController _controller;

  String _query = '';

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();

    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;

    setState(() {
      _query = _controller.text.trim();
    });
  }

  void _submit() {
    final city = _controller.text.trim();

    if (city.isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    widget.onSearch(city);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();

    final recent = widget.recentCities
        .where((city) => city.toLowerCase().contains(query))
        .toList();

    final favorites = widget.favorites
        .where((city) => city.toLowerCase().contains(query))
        .toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: const BoxDecoration(
          color: Color(0xFF0B2239),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Search City',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();

                          Navigator.of(context).pop();
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),

                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'Enter city name...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: _submit,
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                        ),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 17,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (_query.isEmpty && widget.favorites.isNotEmpty) ...[
                        _searchSectionTitle(Icons.star_rounded, 'Favorites'),

                        const SizedBox(height: 10),

                        ...widget.favorites.map(
                          (city) => _searchCityTile(
                            city: city,
                            icon: Icons.star_rounded,
                            iconColor: const Color(0xFFFFD166),
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();

                              widget.onCitySelected(city);
                            },
                          ),
                        ),

                        const SizedBox(height: 22),
                      ],

                      if (recent.isNotEmpty) ...[
                        _searchSectionTitle(
                          Icons.history_rounded,
                          'Recent Searches',
                        ),

                        const SizedBox(height: 10),

                        ...recent.map(
                          (city) => _searchCityTile(
                            city: city,
                            icon: Icons.history_rounded,
                            iconColor: Colors.white.withValues(alpha: 0.55),
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();

                              widget.onCitySelected(city);
                            },
                            trailing: IconButton(
                              tooltip: 'Remove',
                              onPressed: () async {
                                await widget.onRecentRemoved(city);

                                if (!mounted) return;

                                setState(() {});
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.35),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (_query.isNotEmpty &&
                          favorites.isEmpty &&
                          recent.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 70),
                          child: Column(
                            children: [
                              Container(
                                width: 78,
                                height: 78,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: Colors.white.withValues(alpha: 0.35),
                                  size: 38,
                                ),
                              ),

                              const SizedBox(height: 18),

                              const Text(
                                'Search for this city',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              const SizedBox(height: 7),

                              Text(
                                'No saved city matches "$_query"',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 13,
                                ),
                              ),

                              const SizedBox(height: 22),

                              SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: _submit,
                                  icon: const Icon(
                                    Icons.cloud_rounded,
                                    size: 19,
                                  ),
                                  label: const Text('Search Weather'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0B2239),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_query.isEmpty &&
                          widget.favorites.isEmpty &&
                          widget.recentCities.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 75),
                          child: Column(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_city_rounded,
                                  color: Colors.white.withValues(alpha: 0.25),
                                  size: 46,
                                ),
                              ),

                              const SizedBox(height: 18),

                              const Text(
                                'Search for a city',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              const SizedBox(height: 7),

                              Text(
                                'Find weather anywhere in the world',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.40),
                                  fontSize: 13,
                                ),
                              ),

                              const SizedBox(height: 18),

                              Text(
                                'Try searching for Cairo, London,\n'
                                'Dubai or any city.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  fontSize: 11,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.75), size: 18),

        const SizedBox(width: 8),

        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _searchCityTile({
    required String city,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 19),
        ),
        title: Text(
          city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'View weather',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
          ),
        ),
        trailing:
            trailing ??
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.25),
              size: 14,
            ),
      ),
    );
  }
}
