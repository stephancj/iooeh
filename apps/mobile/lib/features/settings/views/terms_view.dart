import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openTerms(BuildContext context, Uri url) async {
  final mode = switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => LaunchMode.inAppWebView,
    _ => LaunchMode.externalApplication,
  };

  try {
    if (await launchUrl(url, mode: mode)) return;
  } on PlatformException {
    // Show the same message if the platform fails to start the view.
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
        content: Text('Impossible d’ouvrir les conditions d’utilisation.')),
  );
}
