import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat/auth_screen.dart';
import 'package:flutter_chat/models/message.dart';
import 'package:flutter_chat/widgets/message_bubble.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _username;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username');
      _userId = prefs.getString('userId');
    });
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Clear local storage on sign out
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _auth.currentUser == null) {
      return;
    }

    try {
      await _firestore.collection('messages').add({
        'text': _messageController.text.trim(),
        'uid': _auth.currentUser!.uid,
        'username': _username ?? 'Guest', // Include username in the message
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Reset typing status after sending the message
      await _firestore.collection('typing').doc(_auth.currentUser!.uid).set({
        'isTyping': false,
      });

      _messageController.clear();
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  Future<void> _updateTypingStatus(bool isTyping) async {
    if (_auth.currentUser == null) return;

    try {
      await _firestore.collection('typing').doc(_auth.currentUser!.uid).set({
        'isTyping': isTyping,
        'username': _username ?? 'Guest',
      });
    } catch (e) {
      debugPrint('Error updating typing status: $e');
    }
  }

  Future<void> _editMessage(Message message) async {
    final TextEditingController editController = TextEditingController(
      text: message.text,
    );

    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Edit Message'),
            content: TextField(
              controller: editController,
              decoration: const InputDecoration(hintText: 'Edit your message'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, editController.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (result != null && result.trim().isNotEmpty) {
      try {
        await _firestore.collection('messages').doc(message.id).update({
          'text': result.trim(),
        });
      } catch (e) {
        debugPrint('Error editing message: $e');
      }
    }
  }

  Future<void> _deleteMessage(Message message) async {
    try {
      await _firestore.collection('messages').doc(message.id).delete();
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat - ${_username ?? 'Guest'}'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: Expanded(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    _firestore
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Something went wrong'));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final messages =
                      snapshot.data!.docs
                          .map((doc) => Message.fromFirestore(doc))
                          .toList();

                  final currentUser = FirebaseAuth.instance.currentUser;

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isCurrentUser = message.uid == currentUser?.uid;
                      return Slidable(
                        endActionPane:
                            isCurrentUser
                                ? ActionPane(
                                  motion: const ScrollMotion(),
                                  children: [
                                    SlidableAction(
                                      onPressed: (_) => _editMessage(message),
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      icon: Icons.edit,
                                      label: 'Edit',
                                    ),
                                    SlidableAction(
                                      onPressed: (_) => _deleteMessage(message),
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      icon: Icons.delete,
                                      label: 'Delete',
                                    ),
                                  ],
                                )
                                : null,
                        child: MessageBubble(
                          message: message,
                          isMe: isCurrentUser,
                          onEdit: () => _editMessage(message),
                          onDelete: () => _deleteMessage(message),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildTypingIndicator(),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) {
                        _updateTypingStatus(text.isNotEmpty);
                      },
                      onSubmitted: (_) {
                        _sendMessage();
                        _updateTypingStatus(false); // Stop typing after sending
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      _sendMessage();
                      _updateTypingStatus(false); // Stop typing after sending
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('typing').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink(); // No one is typing
        }

        final typingUsers =
            snapshot.data!.docs
                .where((doc) => doc['isTyping'] == true && doc.id != _userId)
                .toList();

        if (typingUsers.isEmpty) {
          return const SizedBox.shrink(); // No one else is typing
        }

        final typingUsernames = typingUsers
            .map((doc) => doc['username'] as String)
            .join(', ');

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0),
          child: Text(
            '$typingUsernames is typing...',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
        );
      },
    );
  }
}
