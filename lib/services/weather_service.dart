import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_model.dart';
import '../models/forecast_model.dart';

class WeatherService {
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  static const String _apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');

  // ===========================================================================
  // CURRENT WEATHER - GPS
  // ===========================================================================

  Future<WeatherModel> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/weather'
      '?lat=$latitude'
      '&lon=$longitude'
      '&appid=$_apiKey'
      '&units=metric',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return WeatherModel.fromJson(data);
    }

    if (response.statusCode == 401) {
      throw Exception('Invalid OpenWeather API key');
    }

    throw Exception(
      'Failed to load current weather: '
      '${response.statusCode}',
    );
  }

  // ===========================================================================
  // CURRENT WEATHER - CITY SEARCH
  // ===========================================================================

  Future<WeatherModel> getWeatherByCity(String city) async {
    final url = Uri.parse(
      '$_baseUrl/weather'
      '?q=${Uri.encodeComponent(city)}'
      '&appid=$_apiKey'
      '&units=metric',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return WeatherModel.fromJson(data);
    }

    if (response.statusCode == 401) {
      throw Exception('Invalid OpenWeather API key');
    }

    if (response.statusCode == 404) {
      throw Exception('City not found');
    }

    throw Exception(
      'Failed to search city: '
      '${response.statusCode}',
    );
  }

  // ===========================================================================
  // 5-DAY FORECAST - GPS
  // ===========================================================================

  Future<List<ForecastModel>> getForecast({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      '$_baseUrl/forecast'
      '?lat=$latitude'
      '&lon=$longitude'
      '&appid=$_apiKey'
      '&units=metric',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final List<dynamic> forecastList = data['list'] as List<dynamic>? ?? [];

      final int timezoneOffset =
          (data['city']?['timezone'] as num?)?.toInt() ?? 0;

      return forecastList.map((item) {
        return ForecastModel.fromJson(
          item as Map<String, dynamic>,
          timezoneOffset: timezoneOffset,
        );
      }).toList();
    }

    if (response.statusCode == 401) {
      throw Exception('Invalid OpenWeather API key');
    }

    throw Exception(
      'Failed to load forecast: '
      '${response.statusCode}',
    );
  }

  // ===========================================================================
  // 5-DAY FORECAST - CITY SEARCH
  // ===========================================================================

  Future<List<ForecastModel>> getForecastByCity(String city) async {
    final url = Uri.parse(
      '$_baseUrl/forecast'
      '?q=${Uri.encodeComponent(city)}'
      '&appid=$_apiKey'
      '&units=metric',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final List<dynamic> forecastList = data['list'] as List<dynamic>? ?? [];

      final int timezoneOffset =
          (data['city']?['timezone'] as num?)?.toInt() ?? 0;

      return forecastList.map((item) {
        return ForecastModel.fromJson(
          item as Map<String, dynamic>,
          timezoneOffset: timezoneOffset,
        );
      }).toList();
    }

    if (response.statusCode == 401) {
      throw Exception('Invalid OpenWeather API key');
    }

    if (response.statusCode == 404) {
      throw Exception('City not found');
    }

    throw Exception(
      'Failed to load city forecast: '
      '${response.statusCode}',
    );
  }
}
