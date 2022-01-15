import 'package:dotenv/dotenv.dart';
import 'package:logger/logger.dart';

Logger logger = Logger(
  printer: PrettyPrinter(),
);

Logger loggerNoStack = Logger(
  printer: PrettyPrinter(methodCount: 0),
);

bool kTestMode = false;

class Data {
  static Future<void> init() async {
    load();
  }
}