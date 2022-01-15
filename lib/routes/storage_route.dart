import 'dart:typed_data';

import 'package:byte_size/byte_size.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
// ignore: implementation_imports
import 'package:shelf_router/src/router.dart';
import '../database/database.dart';
import '../database/models/storage/storage.dart';
import '../utilities/data.dart';
import '../utilities/extension.dart';
import 'base_route.dart';

class StorageRoute implements BaseRoute {
  @override
  Router get router {
    final Router router = Router();

    router.post("/create", (Request req) async {
      try {
        Stream<List<int>> stream = req.read();
        String contentType = req.headers["content-type"] ??
            req.headers["Content-Type"] ??
            "application/octet-stream";

        Storage storage = Storage(
            type: StorageType.temp,
            contentType: contentType,
            uuid: Uuid().v4(),
            createAt: DateTime.now().toUtc().millisecondsSinceEpoch);
        GridIn gridIn =
            DataBase.instance.gridFS.createFile(stream, storage.uuid);
        ByteSize size = ByteSize.FromBytes(req.contentLength!);
        if (size.MegaBytes > 8) {
          // 限制最大檔案大小為 8 MB
          return ResponseExtension.badRequest(
              message: "File size is too large");
        }
        await gridIn.save();
        await storage.insert();

        return ResponseExtension.success(data: storage.outputMap());
      } catch (e, stack) {
        logger.e(e, null, stack);
        return ResponseExtension.badRequest();
      }
    });

    router.get("/<uuid>", (Request req) async {
      try {
        String uuid = req.params['uuid']!;
        Storage? storage = await Storage.getByUUID(uuid);
        if (storage == null) {
          return ResponseExtension.notFound();
        }
        return ResponseExtension.success(data: storage.outputMap());
      } catch (e, stack) {
        logger.e(e, null, stack);
        return ResponseExtension.badRequest();
      }
    });

    router.get("/<uuid>/download", (Request req) async {
      try {
        String uuid = req.params['uuid']!;
        Storage? storage = await Storage.getByUUID(uuid);
        if (storage == null) {
          return ResponseExtension.notFound("Storage not found");
        }

        Uint8List? bytes = await storage.readAsBytes();
        if (bytes == null) {
          return ResponseExtension.notFound();
        }

        return Response.ok(bytes, headers: {
          "Content-Type": storage.contentType,
        });
      } catch (e, stack) {
        logger.e(e, null, stack);
        return ResponseExtension.badRequest();
      }
    });

    return router;
  }
}