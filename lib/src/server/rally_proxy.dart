import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:start/start.dart';
import 'package:scrum_tools/src/utils/cache.dart';
import 'package:scrum_tools/src/utils/helpers.dart';
import 'package:logging/logging.dart';

class RallyDevProxy implements ScrumHttpClient {

  static const String _baseUrl =
      'https://rally1.rallydev.com/slm/webservice/v2.0';

  static final Uri _baseUri = Uri.parse(_baseUrl);

  static const String loggerName = "rd-proxy";

  Logger _log = new Logger(loggerName);

  Cache<String, String> _cache;
  HttpClient _httpClient;

  String _user, _pass, _pathRoot;

  RallyDevProxy(this._user, this._pass, [this._pathRoot = '/rd']) {
    _cache = new Cache<String, String>();
    _cache.retriever = _handle;

    HttpClientBasicCredentials credentials =
    new HttpClientBasicCredentials(_user, _pass);

    _httpClient = new HttpClient();
    _httpClient.addCredentials(_baseUri, r'Rally ALM', credentials);
  }

  void init(Server appServer) {
    // Process any 'get' request.
    appServer.get(new RegExp("${_pathRoot}/.*")).listen((Request request) {
      Response response = request.response;
      String path = request.path;
      response.header(r'Content-Type', 'application/json; charset=UTF-8');
      if (path == '${_pathRoot}/status') {
        response.send(r'{"status": "OK"}');
      } else {
        String requestedUri = request.input.requestedUri.toString();
        String uriPart = requestedUri.substring(
            requestedUri.indexOf('${_pathRoot}/') + _pathRoot.length);
        if (uriPart.startsWith(r'/fresh/')) { // Do not use cache
          uriPart = uriPart.substring(uriPart.indexOf(r'/', 1));
          _handle(uriPart).then((String value) {
            response.send(value);
          });
        } else {
          _cache.get(uriPart).then((String value) {
            response.send(value);
          });
        }
      }
    });
    _log.info('Rallydev proxy ready at [${_pathRoot}].');
  }

  // Delegate the call to the Rallydev server.
  Future<String> _handle(String uriPart) {
    Uri uri = Uri.parse('${_baseUrl}${uriPart}');
    Completer <String> completer = new Completer <String>();
    _log.finer('Retrieving -> ${uriPart}');
    _httpClient.getUrl(uri).then((HttpClientRequest request) {
      request.close().then((HttpClientResponse response) {
        StringBuffer sb = new StringBuffer();
        response.transform(UTF8.decoder).listen((content) {
          sb.write(content);
        })
          ..onDone(() {
            completer.complete(sb.toString());
            _log.finer('Retrieved URL -> ${uriPart}');
            _log.finest(() => 'Retrieved content -> ${sb}');
          });
      }).catchError((error) {
        _log.severe(error);
      });
    }).catchError((error) {
      _log.severe(error);
    });
    return completer.future;
  }

  @override
  Future<String> getString(String uriPart) {
    if (uriPart.startsWith(r'/fresh/')) { // Do not use cache
      uriPart = uriPart.substring(uriPart.indexOf(r'/', 1));
      return _handle(uriPart);
    }
    return _cache.get(uriPart);
  }

  @override
  String handleError(dynamic error) => error.toString();

  void close({bool force: false}) {
    _httpClient.close(force: force);
  }
}