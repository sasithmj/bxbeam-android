abstract class PlaybackState {}

class PlaybackInitial extends PlaybackState {}

class PlaybackLoading extends PlaybackState {}

class PlaybackPlaying extends PlaybackState {
  final String url;

  PlaybackPlaying(this.url);
}

class PlaybackError extends PlaybackState {
  final String message;

  PlaybackError(this.message);
}
