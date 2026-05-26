import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const AiChatApp());

class AiChatApp extends StatelessWidget {
  const AiChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แชท AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}

/// ── Models ──────────────────────────────────────────────
enum Role { user, ai }
enum AttachmentType { image, file }

class Attachment {
  final AttachmentType type;
  final String name;
  final int size; // bytes; -1 if unknown
  final Uint8List? bytes; // local file bytes (user upload)
  final String? url; // remote url (AI-generated image)

  const Attachment({
    required this.type,
    required this.name,
    required this.size,
    this.bytes,
    this.url,
  });
}

class Message {
  final Role role;
  final String text;
  final List<Attachment> attachments;
  final DateTime time;
  final bool typing;

  Message({
    required this.role,
    this.text = '',
    this.attachments = const [],
    DateTime? time,
    this.typing = false,
  }) : time = time ?? DateTime.now();
}

/// ── Chat Screen ─────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Message> _messages = [];
  final List<Attachment> _pending = [];

  @override
  void initState() {
    super.initState();
    _messages.addAll([
      Message(
        role: Role.ai,
        text: 'สวัสดีค่ะ! มีอะไรให้ช่วยไหมคะ?\nสามารถส่งข้อความ รูปภาพ หรือไฟล์มาได้เลย',
      ),
    ]);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.bytes == null) continue;
        final isImage = _isImageName(f.name);
        _pending.add(Attachment(
          type: isImage ? AttachmentType.image : AttachmentType.file,
          name: f.name,
          size: f.size,
          bytes: f.bytes,
        ));
      }
    });
  }

  bool _isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  void _removePending(int idx) {
    setState(() => _pending.removeAt(idx));
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;

    setState(() {
      _messages.add(Message(
        role: Role.user,
        text: text,
        attachments: List.of(_pending),
      ));
      _input.clear();
      _pending.clear();
    });
    _scrollToBottom();
    _mockAiReply(text);
  }

  Future<void> _mockAiReply(String userText) async {
    // typing indicator
    setState(() => _messages.add(Message(role: Role.ai, typing: true)));
    _scrollToBottom();

    await Future.delayed(const Duration(milliseconds: 900));

    final hasImage = _messages.isNotEmpty &&
        _messages[_messages.length - 2].attachments
            .any((a) => a.type == AttachmentType.image);

    String reply;
    List<Attachment> atts = [];

    if (hasImage) {
      reply = 'ฉันได้ตรวจสอบรูปภาพที่คุณแนบมาแล้ว ลองสร้างรูปภาพในสไตล์ที่คล้ายกันให้';
      atts.add(Attachment(
        type: AttachmentType.image,
        name: 'ai_generated.jpg',
        size: -1,
        url: 'https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/420/260',
      ));
    } else if (RegExp(r'(รายงาน|เอกสาร|ไฟล์|report|document|file)', caseSensitive: false).hasMatch(userText)) {
      reply = 'นี่คือเอกสารที่สรุปตามที่คุณร้องขอ สามารถดาวน์โหลดได้จากด้านล่าง';
      atts.add(Attachment(
        type: AttachmentType.file,
        name: 'ai_response.txt',
        size: 1248,
        bytes: Uint8List.fromList(
          utf8.encode('เอกสารตอบกลับที่สร้างโดย AI\nคำร้องขอของผู้ใช้: $userText'),
        ),
      ));
    } else if (userText.isNotEmpty) {
      reply = 'นี่คือคำตอบสำหรับ "$userText"\nหากบอกรายละเอียดเพิ่มเติม จะสามารถตอบได้แม่นยำขึ้น';
    } else {
      reply = 'รับทราบค่ะ';
    }

    setState(() {
      _messages.removeLast(); // remove typing
      _messages.add(Message(role: Role.ai, text: reply, attachments: atts));
    });
    _scrollToBottom();
  }

  Future<void> _downloadFile(Attachment a) async {
    if (a.bytes == null) {
      _toast('ไม่มีข้อมูลไฟล์สำหรับดาวน์โหลด');
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${a.name}');
      await file.writeAsBytes(a.bytes!);
      _toast('บันทึกแล้ว: ${file.path}');
    } catch (e) {
      _toast('บันทึกล้มเหลว: $e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _openImage(Attachment a) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageViewer(attachment: a),
    ));
  }

  /// ── Build ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0.5,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              ),
              alignment: Alignment.center,
              child: const Text('AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ผู้ช่วย AI',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.circle, color: Color(0xFF16A34A), size: 8),
                    SizedBox(width: 4),
                    Text('ออนไลน์',
                        style: TextStyle(fontSize: 11, color: Color(0xFF16A34A))),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black54),
            onPressed: () => setState(() {
              _messages.clear();
              _messages.add(Message(
                role: Role.ai,
                text: 'เริ่มการสนทนาใหม่ มีอะไรให้ช่วยไหมคะ?',
              ));
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _MessageBubble(
                  message: _messages[i],
                  onImageTap: _openImage,
                  onFileTap: _downloadFile,
                ),
              ),
            ),
            _Composer(
              controller: _input,
              pending: _pending,
              onPick: _pickFiles,
              onRemove: _removePending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// ── Message Bubble ──────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final Message message;
  final void Function(Attachment) onImageTap;
  final void Function(Attachment) onFileTap;

  const _MessageBubble({
    required this.message,
    required this.onImageTap,
    required this.onFileTap,
  });

  String _formatTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm น.';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == Role.user;
    final bg = isUser ? const Color(0xFF2563EB) : const Color(0xFFF1F3F5);
    final fg = isUser ? Colors.white : const Color(0xFF1F2328);

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.typing)
              const _TypingDots()
            else if (message.text.isNotEmpty)
              Text(message.text,
                  style: TextStyle(color: fg, fontSize: 14, height: 1.5)),
            ...message.attachments.map((a) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: a.type == AttachmentType.image
                      ? _ImageThumb(attachment: a, onTap: () => onImageTap(a))
                      : _FileCard(
                          attachment: a,
                          isUser: isUser,
                          onDownload: () => onFileTap(a),
                        ),
                )),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
              ),
              alignment: Alignment.center,
              child: const Text('AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                bubble,
                if (!message.typing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_formatTime(message.time),
                        style: const TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 11)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onTap;
  const _ImageThumb({required this.attachment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = attachment.bytes != null
        ? Image.memory(attachment.bytes!, fit: BoxFit.cover)
        : Image.network(attachment.url!, fit: BoxFit.cover);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 280),
          child: img,
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final Attachment attachment;
  final bool isUser;
  final VoidCallback onDownload;
  const _FileCard({
    required this.attachment,
    required this.isUser,
    required this.onDownload,
  });

  String _fmtSize(int b) {
    if (b < 0) return '—';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final bg = isUser ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.04);
    final fg = isUser ? Colors.white : const Color(0xFF1F2328);

    return Container(
      width: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description,
                color: Color(0xFF2563EB), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(_fmtSize(attachment.size),
                    style: TextStyle(
                        color: fg.withOpacity(0.7), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.download, color: fg, size: 20),
            onPressed: onDownload,
            tooltip: 'ดาวน์โหลด',
          ),
        ],
      ),
    );
  }
}

/// ── Typing Dots ─────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        Widget dot(double phase) {
          final v = ((_c.value + phase) % 1.0);
          final op = v < 0.5 ? 0.3 + v : 0.3 + (1 - v);
          return Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF9CA3AF).withOpacity(op.clamp(0.3, 1.0)),
              shape: BoxShape.circle,
            ),
          );
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          dot(0.0),
          dot(0.2),
          dot(0.4),
        ]);
      },
    );
  }
}

/// ── Composer ───────────────────────────────────────────
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final List<Attachment> pending;
  final VoidCallback onPick;
  final void Function(int) onRemove;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.pending,
    required this.onPick,
    required this.onRemove,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFECECEC))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending.isNotEmpty)
            SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pending.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _PendingChip(
                  attachment: pending[i],
                  onRemove: () => onRemove(i),
                ),
              ),
            ),
          if (pending.isNotEmpty) const SizedBox(height: 8),
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final canSend =
                  controller.text.trim().isNotEmpty || pending.isNotEmpty;
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.attach_file,
                          color: Color(0xFF6B7280)),
                      onPressed: onPick,
                      tooltip: 'แนบไฟล์',
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: TextField(
                          controller: controller,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'พิมพ์ข้อความ...',
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: canSend
                            ? const Color(0xFF2563EB)
                            : const Color(0xFFC7D2DA),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_upward,
                            color: Colors.white, size: 18),
                        onPressed: canSend ? onSend : null,
                        tooltip: 'ส่ง',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onRemove;
  const _PendingChip({required this.attachment, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isImg = attachment.type == AttachmentType.image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isImg && attachment.bytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    attachment.bytes!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                )
              else
                const Icon(Icons.description, size: 20, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFF6B7280),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// ── Image Viewer ───────────────────────────────────────
class _ImageViewer extends StatelessWidget {
  final Attachment attachment;
  const _ImageViewer({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(attachment.name,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: attachment.bytes != null
              ? Image.memory(attachment.bytes!)
              : Image.network(attachment.url!),
        ),
      ),
    );
  }
}
