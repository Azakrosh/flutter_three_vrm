/// Tracks model ownership for one controller across replace/cancel/reload races.
final class VrmModelSessionState {
  int _loadGeneration = 0;
  bool _isLoading = false;
  bool _isLoaded = false;

  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;

  int beginLoad() {
    _isLoading = true;
    return ++_loadGeneration;
  }

  /// Marks [generation] successful unless a newer operation superseded it.
  bool completeLoad(int generation) {
    if (generation != _loadGeneration) return false;
    _isLoaded = true;
    return true;
  }

  void finishLoad(int generation) {
    if (generation == _loadGeneration) {
      _isLoading = false;
    }
  }

  /// Invalidates a transfer while preserving the currently displayed model.
  void cancelLoad() {
    _loadGeneration += 1;
    _isLoading = false;
  }

  void setLoaded(bool loaded) {
    _isLoaded = loaded;
  }

  /// Invalidates all model work because the owning runtime no longer exists.
  void invalidateRuntime() {
    cancelLoad();
    _isLoaded = false;
  }
}
