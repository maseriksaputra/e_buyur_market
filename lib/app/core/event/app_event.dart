import 'dart:async';

enum AppEvent { productCreated, productUpdated, cartChanged }

class AppEventBus {
  AppEventBus._();
  static final AppEventBus I = AppEventBus._();

  final _ctrl = StreamController<AppEvent>.broadcast();
  Stream<AppEvent> get stream => _ctrl.stream;
  void emit(AppEvent e) => _ctrl.add(e);

  void dispose() { _ctrl.close(); }
}
