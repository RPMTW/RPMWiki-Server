import 'dart:typed_data';

import 'package:byte_size/byte_size.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:rpmtw_server/utilities/api_response.dart';
import 'package:shelf/shelf.dart';
// ignore: implementation_imports
import 'package:shelf_router/src/router.dart';
import '../database/database.dart';
import '../database/models/storage/storage.dart';
import '../utilities/extension.dart';
import 'base_route.dart';

class StorageRoute implements APIRoute {
  @override
  Router get router {
    final Router router = Router();

    router.postRoute("/create", (req, data) async {
      Stream<List<int>> stream = req.read();
      String contentType = req.headers["content-type"] ??
          req.headers["Content-Type"] ??
          "application/octet-stream";

      Storage storage = Storage(
          type: StorageType.temp,
          contentType: contentType,
          uuid: Uuid().v4(),
          createAt: DateTime.now().toUtc().millisecondsSinceEpoch);
      GridIn gridIn = DataBase.instance.gridFS.createFile(stream, storage.uuid);
      ByteSize size = ByteSize.FromBytes(req.contentLength!);
      if (size.MegaBytes > 8) {
        // 限制最大檔案大小為 8 MB
        return APIResponse.badRequest(message: "File size is too large");
      }
      await gridIn.save();
      await storage.insert();

      return APIResponse.success(data: storage.outputMap());
    });

    router.getRoute("/<uuid>", (req, data) async {
      String uuid = data.fields['uuid']!;
      Storage? storage = await Storage.getByUUID(uuid);
      if (storage == null) {
        return APIResponse.notFound();
      }
      return APIResponse.success(data: storage.outputMap());
    });

    router.getRoute("/<uuid>/download", (req, data) async {
      String uuid = data.fields['uuid']!;
      Storage? storage = await Storage.getByUUID(uuid);
      if (storage == null) {
        return APIResponse.notFound("Storage not found");
      }

      Uint8List? bytes = await storage.readAsBytes();
      if (bytes == null) {
        return APIResponse.notFound();
      }

      return Response.ok(bytes, headers: {
        "Content-Type": storage.contentType,
      });
    });

    return router;
  }
}
