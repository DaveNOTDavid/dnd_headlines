import 'package:dnd_headlines/res/strings.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HelperWebViewWidget extends StatelessWidget {

  final String url;
  final String appBarTitle;

  HelperWebViewWidget(this.url, {this.appBarTitle = Strings.appName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle)
      ),
      body: Center(
        child: WebView(
          initialUrl: url,
          javascriptMode: JavascriptMode.unrestricted,
        )
      ),
    );
  }

}
