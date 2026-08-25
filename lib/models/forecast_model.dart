class ForecastModel {
  final DateTime dateTime;

  final double temperature;
  final double feelsLike;

  final int humidity;
  final double windSpeed;

  final String condition;
  final String description;
  final String icon;

  // These are the min/max values for THIS 3-hour forecast period.
  final double minTemperature;
  final double maxTemperature;

  ForecastModel({
    required this.dateTime,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.condition,
    required this.description,
    required this.icon,
    required this.minTemperature,
    required this.maxTemperature,
  });

  factory ForecastModel.fromJson(
    Map<String, dynamic> json, {
    int timezoneOffset = 0,
  }) {
    final main = json['main'] as Map<String, dynamic>? ?? {};
    final wind = json['wind'] as Map<String, dynamic>? ?? {};

    final weatherList = json['weather'] as List<dynamic>? ?? [];

    final weather = weatherList.isNotEmpty
        ? weatherList.first as Map<String, dynamic>
        : <String, dynamic>{};

    final dt = (json['dt'] as num?)?.toInt() ?? 0;

    return ForecastModel(
      dateTime: DateTime.fromMillisecondsSinceEpoch(
        dt * 1000,
        isUtc: true,
      ).add(Duration(seconds: timezoneOffset)),

      temperature: (main['temp'] as num?)?.toDouble() ?? 0.0,

      feelsLike: (main['feels_like'] as num?)?.toDouble() ?? 0.0,

      humidity: (main['humidity'] as num?)?.toInt() ?? 0,

      windSpeed: (wind['speed'] as num?)?.toDouble() ?? 0.0,

      condition: weather['main']?.toString() ?? '',

      description: weather['description']?.toString() ?? '',

      icon: weather['icon']?.toString() ?? '',

      minTemperature: (main['temp_min'] as num?)?.toDouble() ?? 0.0,

      maxTemperature: (main['temp_max'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
