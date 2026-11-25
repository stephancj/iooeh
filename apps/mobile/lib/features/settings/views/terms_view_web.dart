import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

import '../../../core/navigation/trackeo_route.dart';

Future<void> openTerms(BuildContext context, Uri url) async {
  await Navigator.push<void>(
    context,
    TrackeoRoute(builder: (_) => _TermsView(url: url)),
  );
}

class _TermsView extends StatelessWidget {
  const _TermsView({required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    const title = 'Conditions d’utilisation';
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: [
          IconButton(
            tooltip: 'Ouvrir dans le navigateur',
            onPressed: () => launchUrl(url, webOnlyWindowName: '_blank'),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: (element) {
            final frame = element as web.HTMLIFrameElement;
            frame
              ..src = url.toString()
              ..title = title;
            frame.style
              ..width = '100%'
              ..height = '100%'
              ..border = '0';
          },
        ),
      ),
    );
  }
}
