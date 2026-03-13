// Template : extensions utilitaires pour un projet Flutter.
// Copier ce fichier dans lib/widgets/extensions.dart et adapter selon les besoins.

import "package:flutter/material.dart";

extension BuildContextNavigation on BuildContext {
  /// Push a [MaterialPageRoute] for the given [builder].
  Future<T?> push<T>(WidgetBuilder builder) =>
      Navigator.push<T>(this, MaterialPageRoute(builder: builder));

  /// Push a [MaterialPageRoute] displaying the given [page] widget.
  Future<T?> pushPage<T>(Widget page) =>
      Navigator.push<T>(this, MaterialPageRoute(builder: (_) => page));

  /// Pop the current route, optionally returning [result].
  void pop<T>([T? result]) => Navigator.pop<T>(this, result);
}

extension WidgetExtension on Widget {
  Widget tooltip(String message) =>
      message.isEmpty ? this : Tooltip(message: message, child: this);

  Widget sized({double? width, double? height}) =>
      SizedBox(width: width, height: height, child: this);
}
