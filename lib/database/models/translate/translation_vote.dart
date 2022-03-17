import 'dart:convert';

class TranslationVote {
  final TranslationVoteType type;
  final String userUUID;

  bool get isUpVote => type == TranslationVoteType.up;
  bool get isDownVote => type == TranslationVoteType.down;

  const TranslationVote(this.type, this.userUUID);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TranslationVote &&
        other.type == type &&
        other.userUUID == userUUID;
  }

  @override
  int get hashCode => type.hashCode ^ userUUID.hashCode;

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'userUUID': userUUID,
    };
  }

  factory TranslationVote.fromMap(Map<String, dynamic> map) {
    return TranslationVote(
      TranslationVoteType.values.byName(map['type']),
      map['userUUID'],
    );
  }
}

enum TranslationVoteType { up, down }
