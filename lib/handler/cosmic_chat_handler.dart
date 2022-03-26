import "dart:convert";
import "dart:io";

import "package:dotenv/dotenv.dart";
import "package:http/http.dart" as http;
import "package:mongo_dart/mongo_dart.dart";
import "package:rpmtw_server/database/models/auth/ban_info.dart";
import "package:rpmtw_server/database/models/cosmic_chat/cosmic_chat_message.dart";
import "package:rpmtw_server/utilities/scam_detection.dart";
import "package:rpmtw_server/utilities/utility.dart";
import "package:socket_io/socket_io.dart";

import "package:rpmtw_server/database/models/auth/user.dart";
import "package:rpmtw_server/utilities/data.dart";

class CosmicChatHandler {
  static late final Server _io;

  static Server get io => _io;

  /// Number of online users.
  static int get onlineUsers => _io.sockets.sockets.length;

  static final List<String> _cachedMinecraftUUIDs = [];

  Future<void> init() async {
    /// 2087 is cloudflare supported proxy https port
    int port = int.parse(env["COSMIC_CHAT_PORT"] ?? "2087");
    _io = Server();
    final InternetAddress ip = InternetAddress.anyIPv4;

    try {
      eventHandler(io);
      await io.listen(port);
      loggerNoStack
          .i("Cosmic Chat Server listening on port http://${ip.host}:$port");
    } catch (e) {
      loggerNoStack.e("Cosmic Chat Server error: $e");
    }
  }

  void eventHandler(Server io) {
    io.on("connection", (client) {
      if (client is Socket) {
        clientMessageHandler(client);
        discordMessageHandler(client);
      }
    });
  }

  void clientMessageHandler(Socket client) {
    try {
      List<bool> initCheckList = List<bool>.generate(3, (index) => false);
      Map<String, dynamic> headers = {};
      client.request.headers.forEach((name, values) {
        headers[name] = values;
      });
      final String? token = headers["rpmtw_auth_token"]?[0];
      final String? minecraftUUID = headers["minecraft_uuid"]?[0];
      final InternetAddress ip = InternetAddress(headers["CF-Connecting-IP"] ??
          client.request.connectionInfo!.remoteAddress.address);

      String? minecraftUsername;
      bool minecraftUUIDValid = false;
      User? user;
      if (token != null) {
        fetch() async {
          try {
            User? _user = await User.getByToken(token);
            user = _user;
            initCheckList[0] = true;
          } catch (e) {
            user = null;
            initCheckList[0] = true;
            client.error("Invalid rpmtw account token");
          }
        }

        fetch();
      } else {
        initCheckList[0] = true;
      }

      if (minecraftUUID != null) {
        if (_cachedMinecraftUUIDs.contains(minecraftUUID)) {
          initCheckList[1] = true;
        }

        /// Verify that the minecraft account exists
        http
            .get(Uri.parse(
                "https://sessionserver.mojang.com/session/minecraft/profile/$minecraftUUID"))
            .then((response) {
          if (response.statusCode == 200) {
            Map data = json.decode(response.body);
            minecraftUUIDValid = true;
            minecraftUsername = data["name"];
            _cachedMinecraftUUIDs.add(minecraftUUID);
          }

          initCheckList[1] = true;
        });
      } else {
        initCheckList[1] = true;
      }

      BanInfo? banInfo;
      fetch() async {
        banInfo = await BanInfo.getByIP(ip.address);
        initCheckList[2] = true;
      }

      fetch();

      bool isInit() => initCheckList.reduce((a, b) => a && b);
      bool isAuthenticated() =>
          user != null || (minecraftUUIDValid && minecraftUsername != null);

      client.on("clientMessage", (_data) async {
        final bool init = isInit();
        final List dataList = _data as List;
        late final List bytes =
            dataList.first is List ? dataList.first : dataList;
        late final Function? ack =
            dataList.last is Function ? dataList.last : null;

        /// The server has not completed the initialization process and therefore does not process the message.
        if (!init) {
          return;
        }

        if (!isAuthenticated()) {
          return ack?.call(json.encode({
            "status": "unauthorized",
          }));
        }
        if (banInfo != null) {
          return ack?.call(json.encode({
            "status": "banned",
          }));
        }

        Map data = json.decode(utf8.decode((bytes).cast<int>()));
        String? message = data["message"];

        if (message != null && message.isNotEmpty) {
          String username = user?.username ?? minecraftUsername!;
          String? userUUID = user?.uuid;
          String? nickname = data["nickname"];
          String? replyMessageUUID = data["replyMessageUUID"];

          if (user?.uuid == "07dfced6-7d41-4660-b2b4-25ba1319b067") {
            username = "RPMTW 維護者兼創辦人";
          }

          late String avatar;

          if (userUUID != null) {
            avatar =
                "${kTestMode ? "http://localhost:8080" : "https://api.rpmtw.com:2096"}/storage/$userUUID/download";
          } else if (minecraftUUID != null) {
            avatar = "https://crafthead.net/avatar/$minecraftUUID.png";
          }

          if (replyMessageUUID != null) {
            CosmicChatMessage? replyMessage =
                await CosmicChatMessage.getByUUID(replyMessageUUID);
            if (replyMessage == null) {
              return client.error("Invalid reply message UUID");
            }
          }

          CosmicChatMessage msg = CosmicChatMessage(
              uuid: Uuid().v4(),
              username: username,
              message: message,
              nickname: nickname,
              avatarUrl: avatar,
              sentAt: Utility.getUTCTime(),
              ip: ip,
              userType: user != null
                  ? CosmicChatUserType.rpmtw
                  : CosmicChatUserType.minecraft,
              replyMessageUUID: replyMessageUUID);
          sendMessage(msg, ack: ack);
        }
      });
    } catch (e, stackTrace) {
      logger.e(
          "[Cosmic Chat] Throwing errors when handling client messages: $e",
          null,
          stackTrace);
    }
  }

  void discordMessageHandler(Socket client) {
    try {
      final String? clientDiscordSecretKey =
          client.handshake?["headers"]?["discord_secretKey"]?[0];
      final String serverDiscordSecretKey =
          env["COSMIC_CHAT_DISCORD_SecretKey"]!;
      final bool isValid = clientDiscordSecretKey == serverDiscordSecretKey;

      /// Verify that the message is sent by the [RPMTW Discord Bot](https://github.com/RPMTW/RPMTW-Discord-Bot) and not a forged message from someone else.
      if (!isValid) return;
      client.on("discordMessage", (_data) async {
        Map data = json.decode(utf8.decode(List<int>.from(_data)));

        String? message = data["message"];
        String? username = data["username"];
        String? avatarUrl = data["avatarUrl"];
        String? nickname = data["nickname"];
        String? replyMessageUUID = data["replyMessageUUID"];

        if (message == null ||
            message.isEmpty ||
            username == null ||
            username.isEmpty ||
            avatarUrl == null ||
            avatarUrl.isEmpty) return client.error("Invalid discord message");

        if (replyMessageUUID != null) {
          CosmicChatMessage? replyMessage =
              await CosmicChatMessage.getByUUID(replyMessageUUID);
          if (replyMessage == null) {
            return client.error("Invalid reply message UUID");
          }
        }

        CosmicChatMessage msg = CosmicChatMessage(
            uuid: Uuid().v4(),
            username: username,
            message: message,
            nickname: nickname,
            avatarUrl: avatarUrl,
            sentAt: Utility.getUTCTime(),
            ip: client.request.connectionInfo!.remoteAddress,
            userType: CosmicChatUserType.discord,
            replyMessageUUID: replyMessageUUID);
        sendMessage(msg);
      });
    } catch (e, stackTrace) {
      logger.e(
          "[Cosmic Chat] Throwing errors when handling discord messages: $e",
          null,
          stackTrace);
    }
  }

  Future<void> sendMessage(CosmicChatMessage msg, {Function? ack}) async {
    bool phishing = ScamDetection.detection(msg.message);

    /// Detect phishing
    if (phishing) {
      return ack?.call(json.encode({
        "status": "phishing",
      }));
    } else {
      await msg.insert();

      /// Use utf8 encoding to avoid some characters (e.g. Chinese, Japanese) cannot be parsed.
      io.emit("sentMessage", utf8.encode(json.encode(msg.outputMap())));
      ack?.call(json.encode({"status": "success"}));
    }
  }
}
