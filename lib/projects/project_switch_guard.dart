/// Shared by the recorder and project switching, including paused captures.
class ProjectSwitchGuard {
  static final Map<Object, bool Function()> _recorders = {};
  static bool switching = false;
  static bool get recording => _recorders.values.any((active) => active());
  static void register(Object owner, bool Function() active) =>
      _recorders[owner] = active;
  static void unregister(Object owner) => _recorders.remove(owner);
}
