import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> writeCredentialsFile() async {
  const String accessToken = String.fromEnvironment("OAUTH_ACCESS_TOKEN");
  const String refreshToken = String.fromEnvironment("OAUTH_REFRESH_TOKEN");
  const Map<String, dynamic> credentialsData = {
    "accessToken": accessToken,
    "refreshToken": refreshToken,
    "tokenEndpoint": "https://accounts.google.com/o/oauth2/token",
    "scopes": ["https://www.googleapis.com/auth/userinfo.email", "openid"],
    "expiration": 1649529671122,
  };

  final File file = File(p.join("~", ".pub-cache", "credentials.json"));
  await file.writeAsString(json.encode(credentialsData));
}

void main() async {
  await writeCredentialsFile();
}