class WeatherModel {
  final String cityName;
  final String country;

  final double latitude;
  final double longitude;

  final int timezoneOffset;

  final double temperature;
  final double feelsLike;

  final double minTemperature;
  final double maxTemperature;

  final int humidity;
  final int pressure;

  final double windSpeed;

  final int visibility;
  final int clouds;

  final String condition;
  final String description;
  final String icon;

  final DateTime sunrise;
  final DateTime sunset;

  WeatherModel({
    required this.cityName,
    required this.country,

    required this.latitude,
    required this.longitude,

    required this.timezoneOffset,

    required this.temperature,
    required this.feelsLike,

    required this.minTemperature,
    required this.maxTemperature,

    required this.humidity,
    required this.pressure,

    required this.windSpeed,

    required this.visibility,
    required this.clouds,

    required this.condition,
    required this.description,
    required this.icon,

    required this.sunrise,
    required this.sunset,
  });

  factory WeatherModel.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>? ?? {};

    final wind = json['wind'] as Map<String, dynamic>? ?? {};

    final cloudsData = json['clouds'] as Map<String, dynamic>? ?? {};

    final sys = json['sys'] as Map<String, dynamic>? ?? {};

    final weatherList = json['weather'] as List<dynamic>? ?? [];

    final weather = weatherList.isNotEmpty
        ? weatherList.first as Map<String, dynamic>
        : <String, dynamic>{};

    final coord = json['coord'] as Map<String, dynamic>? ?? {};

    final timezoneOffset = (json['timezone'] as num?)?.toInt() ?? 0;

    final sunriseTimestamp = (sys['sunrise'] as num?)?.toInt() ?? 0;

    final sunsetTimestamp = (sys['sunset'] as num?)?.toInt() ?? 0;

    return WeatherModel(
      cityName: json['name']?.toString() ?? '',

      country: sys['country']?.toString() ?? '',

      latitude: (coord['lat'] as num?)?.toDouble() ?? 0.0,

      longitude: (coord['lon'] as num?)?.toDouble() ?? 0.0,

      timezoneOffset: timezoneOffset,

      temperature: (main['temp'] as num?)?.toDouble() ?? 0.0,

      feelsLike: (main['feels_like'] as num?)?.toDouble() ?? 0.0,

      minTemperature: (main['temp_min'] as num?)?.toDouble() ?? 0.0,

      maxTemperature: (main['temp_max'] as num?)?.toDouble() ?? 0.0,

      humidity: (main['humidity'] as num?)?.toInt() ?? 0,

      pressure: (main['pressure'] as num?)?.toInt() ?? 0,

      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0.0,

      visibility: (json['visibility'] as num?)?.toInt() ?? 0,

      clouds: (cloudsData['all'] as num?)?.toInt() ?? 0,

      condition: weather['main']?.toString() ?? '',

      description: weather['description']?.toString() ?? '',

      icon: weather['icon']?.toString() ?? '',

      sunrise: DateTime.fromMillisecondsSinceEpoch(
        sunriseTimestamp * 1000,
        isUtc: true,
      ).add(Duration(seconds: timezoneOffset)),

      sunset: DateTime.fromMillisecondsSinceEpoch(
        sunsetTimestamp * 1000,
        isUtc: true,
      ).add(Duration(seconds: timezoneOffset)),
    );
  }
}
