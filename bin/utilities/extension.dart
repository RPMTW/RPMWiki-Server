import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

class ResponseExtension {
  static Response badRequest() => Response(HttpStatus.badRequest,
      body: json.encode({
        'status': HttpStatus.badRequest,
        'message': 'Bad Request',
      }),
      headers: {'content-type': 'application/json'});

  static Response success({required Map data}) => Response(HttpStatus.ok,
      body: json.encode(
          {'status': HttpStatus.ok, 'message': 'success', 'data': data}),
      headers: {'content-type': 'application/json'});

  static Response internalServerError() =>
      Response(HttpStatus.internalServerError,
          body: json.encode({
            'status': HttpStatus.internalServerError,
            'message': 'Internal Server Error',
          }),
          headers: {'content-type': 'application/json'});
}
