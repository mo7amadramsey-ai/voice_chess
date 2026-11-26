import 'package:flutter/material.dart';
import '../core/game_controller.dart';
import '../core/levels.dart';
import 'board_view.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final c = GameController();
  final text = TextEditingController();

  @override
  void initState() {
    super.initState();
    c.init();
  }

  @override
  void dispose() {
    c.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('شطرنج صوتي', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          actions: [
            TextButton.icon(onPressed: _pickLevel, icon: const Icon(Icons.speed), label: Text('${c.level.index} · ${c.level.elo}')),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              _banner(),
              const SizedBox(height: 10),
              BoardView(c),
              const SizedBox(height: 10),
              _moves(),
              const Spacer(),
              if (c.heard.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('سمعتُ: ${c.heard}', style: const TextStyle(color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              _typeBox(),
              const SizedBox(height: 10),
              _controls(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _banner() => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: c.thinking ? const Color(0x33D4A24C) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          if (c.thinking) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          if (c.thinking) const SizedBox(width: 10),
          Expanded(child: Text(c.banner, style: const TextStyle(fontSize: 16))),
        ]),
      );

  Widget _moves() {
    final items = <String>[];
    for (var i = 0; i < c.sans.length; i += 2) {
      items.add('${i ~/ 2 + 1}. ${c.sans[i]}${i + 1 < c.sans.length ? '  ${c.sans[i + 1]}' : ''}');
    }
    return SizedBox(
      height: 30,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          children: [for (final m in items.reversed) Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: Text(m, style: const TextStyle(color: Colors.white70))))],
        ),
      ),
    );
  }

  Widget _typeBox() => TextField(
        controller: text,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          hintText: 'اكتب أمرًا مثل: حصان اف 3  /  نيو جيم وايت',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSubmitted: (v) {
          if (v.trim().isEmpty) return;
          c.handleSpeech(v);
          text.clear();
        },
      );

  Widget _controls() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(tooltip: 'لعبة جديدة', onPressed: _newGameSheet, icon: const Icon(Icons.add_circle_outline)),
          IconButton(tooltip: 'تراجع', onPressed: c.undo, icon: const Icon(Icons.undo)),
          GestureDetector(
            onTap: c.toggleVoice,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: c.voiceOn ? 76 : 68,
              height: c.voiceOn ? 76 : 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.voiceOn ? const Color(0xFFE5484D) : const Color(0xFFD4A24C),
                boxShadow: [BoxShadow(color: (c.voiceOn ? const Color(0xFFE5484D) : const Color(0xFFD4A24C)).withOpacity(0.5), blurRadius: c.voiceOn ? 28 : 12)],
              ),
              child: Icon(c.voiceOn ? Icons.mic : Icons.mic_none, size: 34, color: Colors.black87),
            ),
          ),
          IconButton(tooltip: 'تلميح', onPressed: c.hint, icon: const Icon(Icons.lightbulb_outline)),
          IconButton(tooltip: 'اقلب اللوحة', onPressed: c.flip, icon: const Icon(Icons.swap_vert)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            onSelected: (v) {
              if (v == 'sound') c.toggleSound();
              if (v == 'ar' || v == 'en') c.setLang(v);
              if (v == 'resign') c.resign();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'sound', child: Text(c.soundOn ? 'كتم الصوت' : 'تشغيل الصوت')),
              PopupMenuItem(value: c.lang == 'ar' ? 'en' : 'ar', child: Text(c.lang == 'ar' ? 'English voice + listening' : 'العربية: صوت واستماع')),
              const PopupMenuItem(value: 'resign', child: Text('استسلام')),
            ],
          ),
        ],
      );

  void _pickLevel() => showModalBottomSheet(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('مستوى الخصم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final l in kLevels)
                  ChoiceChip(
                    label: Text('${l.index} · ${l.elo}'),
                    selected: c.level.index == l.index,
                    onSelected: (_) {
                      c.pickLevel(l);
                      Navigator.pop(context);
                    },
                  ),
              ]),
            ]),
          ),
        ),
      );

  void _newGameSheet() => showModalBottomSheet(
        context: context,
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('لعبة جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              for (final o in const [('ألعب بالأبيض', true), ('ألعب بالأسود', false)])
                ListTile(
                  title: Text(o.$1),
                  onTap: () {
                    Navigator.pop(context);
                    c.newGame(white: o.$2);
                  },
                ),
            ]),
          ),
        ),
      );
}
