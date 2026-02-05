import 'package:flutter/material.dart';
import 'chat_detail_page.dart';

class GroupChatDetailPage extends StatelessWidget {
  final String chatId;
  final String chatName;

  const GroupChatDetailPage({super.key, required this.chatId, required this.chatName});

  @override
  Widget build(BuildContext context) {
    return ChatDetailPage(chatId: chatId, chatName: chatName);
  }
}
