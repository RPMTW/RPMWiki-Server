import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:mongo_dart/mongo_dart.dart';

class DataBase {
  static late Db _db;

  static Future<void> init() async {
    InternetAddress ip = InternetAddress.anyIPv4;

    String username = env['DATA_BASE_USERNAME']!;
    String password = env['DATA_BASE_PASSWORD']!;
    String host = env['DATA_BASE_HOST']!;
    String port = env['DATA_BASE_PORT']!;
    String name = env['DATA_BASE_NAME']!;

    String url =
        "mongodb+srv://$username:$password@$host:$port/$name";

    print(url);

    _db = await Db.create(url);
    await _db.open();
  }

  static Db get instance => _db;
}
