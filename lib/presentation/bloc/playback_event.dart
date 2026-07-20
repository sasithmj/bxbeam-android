abstract class PlaybackEvent {}

/// Triggered when the app starts or when the presentation layer is ready
class PlaybackStarted extends PlaybackEvent {}

/// Triggered internally when the PlaybackEngine ticks and produces a new URL
class PlaybackUrlUpdated extends PlaybackEvent {
  final String url;

  PlaybackUrlUpdated(this.url);
}

/// Triggered (e.g., via WebSocket) when the schedule needs to be updated
class PlaybackSchedulesUpdated extends PlaybackEvent {}
