import 'dart:convert';

import 'package:dnd_headlines/res/dimens.dart';
import 'package:dnd_headlines/util/widget/helper_webview_widget.dart';
import 'package:flutter/material.dart';

import 'package:dnd_headlines/app/dnd_headlines_app.dart';
import 'package:dnd_headlines/model/headline_response.dart';
import 'package:dnd_headlines/util/helper_functions.dart';
import 'package:dnd_headlines/util/widget/helper_text_widget.dart';
import 'package:dnd_headlines/util/widget/helper_progress_bar_widget.dart';
import 'package:dnd_headlines/res/strings.dart';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_picker/flutter_picker.dart';
import 'package:newsapi_client/newsapi_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fields used throughout this file.
String _newsApiKey;

void main() => runApp(DndHeadlinesRootWidget());

/// Root widget responsible for laying out the home screen of the app. Aside 
/// from theme and styling, a [FutureBuilder] is used to reactively build out 
/// the widget as soon as the latest [AsyncSnapshot]'s tasks are completed 
/// (with the [Future] returned.
class DndHeadlinesRootWidget extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
      ),
      home: FutureBuilder<Headline>(
        future: _initDataAndGetHeadlines(),
        builder: (BuildContext context, AsyncSnapshot<Headline> snapshot) {
          if (snapshot.hasData) {
            return HeadlineWidget(headline: snapshot.data);
          } else if (snapshot.hasError) {
            return DndTextViewWidget(text: Strings.errorEmptyStateViewGetNewsSources,);
          } else {
            return DndProgressIndicatorWidget();
          }
        }
      ),
    );
  }

  Future<Headline> _initDataAndGetHeadlines() async {
    final remoteConfig = await getRemoteConfig();	
    _newsApiKey = remoteConfig.getString(Strings.newsApiKey);

    return getNewsSources();
  }

}

/// A subclass of the "listenable" widget, [AnimatedWidget], that rebuilds 
/// itself every time there's a diff between [Headline] data. This is 
/// possible since [Headline] implements a listenable.
class HeadlineWidget extends AnimatedWidget {

  final Headline headline;

  HeadlineWidget({@required this.headline}) : super(listenable: headline);

  /// Lays out the top [Headline] news data via a [ListView] should there be data,
  /// otherwise an empty view is shown. A user can also change the news publisher 
  /// (which will fire off the listener), or maybe refresh the data.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(headline.getPublisherName() ?? Strings.appName),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.collections_bookmark),
            alignment: Alignment.centerRight,
            onPressed: () {
              _showPickerDialog(context);
            },
          )
        ],
      ),
      body: _getHeadlineListViewWidget(),
      bottomNavigationBar: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => HelperWebViewWidget(Strings.newsApiUrl)
            ),
          );
        },
        child: Image.asset(Strings.newsApiAttributionImgPath)),
    );
  }

  Widget _getHeadlineListViewWidget() {
    /// Retrieves the articles from the [Headline] listenable object, and then 
    /// filters out the articles that don't qualify with say, respective properties 
    /// that are either null or blank for instance.
    final articles = headline.articles ?? [];
    final filteredArticles = articles.where(((item) => (!(HelperFunctions.isNullOrBlank(item.title))))).toList();

    return RefreshIndicator(
      child: filteredArticles.isNotEmpty
        ? ListView.builder(
          itemCount: filteredArticles.length,
          physics: const AlwaysScrollableScrollPhysics(),
          itemBuilder: (BuildContext context, int index) {
            final article = filteredArticles[index];
            DndHeadlinesApp.log('Article: $article');
            
            return Card(
              child: ListTile(
                title: Text(article.title),
                subtitle: Text(HelperFunctions.getTimeDifference(article.publishedAt)),
                contentPadding: EdgeInsets.fromLTRB(
                    Dimens.paddingDefault,
                    (index == 0) ? Dimens.paddingOneHalf : 0.0,
                    Dimens.paddingDefault,
                    Dimens.paddingOneHalf
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => 
                      HelperWebViewWidget(
                        article.url,
                        appBarTitle: article.title,
                      )
                    )
                  );
                }
              ),
            );
          })
        : Center(child: Text(Strings.errorEmptyStateViewGetNewsSources)),
      onRefresh: () async {
        await getNewsSources()
            .then((headline) => this.headline.setHeadline(headline))
            .catchError((error) => DndHeadlinesApp.log(error));
      }
    );
  }

  /// Displays a [Picker] dialog of a list of news publisher options after 
  /// decoding the news source JSON metadata.
  void _showPickerDialog(BuildContext context) async {
    final newsSources = await loadNewsSourcesJson(context);
    final sourceNames = newsSources.map((source) => source.name).toList();

    new Picker(
      adapter: PickerDataAdapter<String>(pickerdata: sourceNames),
      hideHeader: true,
      title: new Text(Strings.newsSourcePickerDialogTitle),
      onConfirm: (Picker picker, List value) {
        _onNewsSourceSelected(newsSources, value);
      }
    ).showDialog(context);
  }

  /// Handles the news publisher selected from the [Picker] such as retrieving 
  /// [Headline] data with the selected source's ID (and sets and caches it), and 
  /// then rebuilds this widget with new data.
  void _onNewsSourceSelected(List<Source> newsSources, List value) async {
    final sourceId = newsSources[value[0]].id;
    await setNewsSourcePrefId(sourceId);

    await getNewsSources()
        .then((headline) => this.headline.setHeadline(headline))
        .catchError((error) => DndHeadlinesApp.log(error));
  }

}

/// Returns a list of [Source]s after decoding the static JSON metadata file.
Future<List<Source>> loadNewsSourcesJson(BuildContext context) async {
  String data = await DefaultAssetBundle.of(context).loadString(Strings.newsSourceJsonPath);
  final jsonResult = json.decode(data);
  final newsSources = (jsonResult as List).map((e) => Source.fromJson(e)).toList();

  return newsSources;
}

/// Returns the cached news source publisher ID.
Future<String> getNewsSourcePrefId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(Strings.newsSourcePrefKey) ?? Strings.newsSourcePrefIdDefault;
}

/// Caches the news source publisher ID for future sessions.
Future<void> setNewsSourcePrefId(String sourceId) async {
  final prefs = await SharedPreferences.getInstance();
  prefs.setString(Strings.newsSourcePrefKey, sourceId);
}

/// GET call for news source data.
Future<Headline> getNewsSources() async {
  /// JSON decoding occurs deep under the hood within the following News API 
  /// package implementation.
  final sourceId = await getNewsSourcePrefId();
  final client = NewsapiClient(_newsApiKey);
  final sourceList = [sourceId];
  final response = await client.request(TopHeadlines(
      sources: sourceList /// Source ID as the identifier
  ));
  final headline = Headline.fromJson(response);
  headline.log();

  return headline;
}

Future<RemoteConfig> getRemoteConfig() async {	
  final RemoteConfig remoteConfig = await RemoteConfig.instance;	

  /// Enables developer mode to relax fetch throttling.	
  remoteConfig.setConfigSettings(RemoteConfigSettings(debugMode: true));	
  remoteConfig.setDefaults(<String, dynamic>{	
    Strings.newsApiKey: "",	
  });	

  try {	
    /// Using default duration to force fetching from remote server.	
    await remoteConfig.fetch(expiration: const Duration(seconds: 0));	
    await remoteConfig.activateFetched();	
  } on FetchThrottledException catch (exception) {	
    print(exception);	
  } catch (exception) {	
    print(Strings.errorMsgExceptionRemoteConfig);	
  }	

  return remoteConfig;	
}
