/// Arama sayfası: kullanıcı, hashtag, metin arama.
///
/// Relay'den `REQ` ile filtrelenmiş event'ler alınır, client-side'da
/// sıralama/filtreleme yapılır. Son aramalar Keystore'da saklanır.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/identity/key_storage.dart';
import '../../core/nostr/bech32.dart';
import '../../core/nostr/event.dart';
import '../../core/nostr/keys.dart';
import '../../core/nostr/relay_client.dart';
import '../../core/session/app_session.dart';
import '../../core/stories/story.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../feed/post_tile.dart';
import '../feed/user_sheet.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  SearchMode _mode = SearchMode.people;
  bool _searching = false;
  List<SearchResult> _results = [];
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() => _query = _controller.text.trim());
    });
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final storage = KeyStorage();
    final raw = await storage.read(key: 'recent_searches');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        setState(() => _recentSearches = list);
      } catch (_) {}
    }
  }

  Future<void> _saveRecentSearch(String query) async {
    if (query.isEmpty) return;
    final storage = KeyStorage();
    final list = [..._recentSearches];
    list.remove(query);
    list.insert(0, query);
    if (list.length > 10) list.removeRange(10, list.length);
    await storage.write(key: 'recent_searches', value: jsonEncode(list));
    setState(() => _recentSearches = list);
  }

  Future<void> _search() async {
    if (_query.isEmpty || _searching) return;
    setState(() => _searching = true);
    await _saveRecentSearch(_query);

    try {
      List<SearchResult> results;
      switch (_mode) {
        case SearchMode.people:
          results = await _searchPeople(_query);
          break;
        case SearchMode.hashtags:
          results = await _searchHashtags(_query);
          break;
        case SearchMode.posts:
          results = await _searchPosts(_query);
          break;
      }
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<List<SearchResult>> _searchPeople(String query) async {
    final session = AppSession.instance;
    final lower = query.toLowerCase();
    final results = <SearchResult>[];

    // Local profiles first
    for (final entry in session.profiles.entries) {
      final profile = entry.value;
      final name = profile.displayName.toLowerCase();
      final pubkey = entry.key.toLowerCase();
      if (name.contains(lower) || pubkey.startsWith(lower)) {
        results.add(SearchResult.profileResult(profile));
      }
    }

    // If query looks like npub/pubkey, try fetch from relay
    if (query.startsWith('npub1') || (query.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(query))) {
      final pubkey = query.startsWith('npub1')
          ? _npubToHex(query)
          : query.toLowerCase();
      if (pubkey != null && !session.profiles.containsKey(pubkey)) {
        await _fetchProfileFromRelay(pubkey);
        if (mounted && session.profiles.containsKey(pubkey)) {
          results.insert(0, SearchResult.profileResult(session.profiles[pubkey]!));
        }
      }
    }

    return results;
  }

  Future<void> _fetchProfileFromRelay(String pubkey) async {
    final client = RelayClient(AppConfig.relayUrl);
    try {
      await client.connect();
      final completer = Completer<void>();
      final sub = client.subscribe('search-profile', [
        {'kinds': [EventKind.profile], 'authors': [pubkey], 'limit': 1}
      ]);
      client.events.listen((event) {
        if (event.kind == EventKind.profile && event.pubkey == pubkey) {
          AppSession.instance.ingestEvent(event);
          completer.complete();
        }
      });
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {}
    finally {
      await client.dispose();
    }
  }

  String? _npubToHex(String npub) {
    try {
      final decoded = bech32Decode(npub);
      if (decoded.hrp != 'npub' || decoded.data.length != 32) return null;
      return bytesToHex(decoded.data);
    } catch (_) {
      return null;
    }
  }

  Future<List<SearchResult>> _searchHashtags(String query) async {
    final session = AppSession.instance;
    final tag = query.startsWith('#') ? query.substring(1).toLowerCase() : query.toLowerCase();
    final results = <SearchResult>[];

    for (final note in session.notes) {
      if (note.kind != EventKind.note) continue;
      for (final t in note.tags) {
        if (t.length >= 2 && t[0] == 't' && t[1].toLowerCase().contains(tag)) {
          results.add(SearchResult.hashtagResult(t[1], note));
          break;
        }
      }
    }
    return results;
  }

  Future<List<SearchResult>> _searchPosts(String query) async {
    final session = AppSession.instance;
    final lower = query.toLowerCase();
    final results = <SearchResult>[];

    for (final note in session.notes) {
      if (note.kind != EventKind.note) continue;
      if (Story.isStory(note)) continue;
      if (note.content.toLowerCase().contains(lower)) {
        results.add(SearchResult.postResult(note));
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ara'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Kullanıcı, #hashtag, metin ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Mode tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (final mode in SearchMode.values)
                  Expanded(
                    child: ChoiceChip(
                      label: Text(_modeLabel(mode)),
                      selected: _mode == mode,
                      onSelected: (_) => setState(() => _mode = mode),
                      selectedColor: AppColors.accent.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: _mode == mode ? AppColors.accent : AppColors.textMuted,
                        fontWeight: _mode == mode ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty && _query.isEmpty
                    ? _buildRecentSearches()
                    : _results.isEmpty
                        ? EmptyState(
                            icon: Icons.search_off,
                            title: 'Sonuç bulunamadı',
                            message: '"$_query" için sonuç yok.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _results.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, i) => _ResultTile(result: _results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Arama geçmişi boş',
        message: 'Arama yaptıkça son aramalar burada görünecek.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionLabel('Son aramalar'),
        const SizedBox(height: Insets.sm),
        for (final q in _recentSearches)
          ListTile(
            leading: const Icon(Icons.history, color: AppColors.textMuted),
            title: Text(q),
            onTap: () {
              _controller.text = q;
              _search();
            },
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => _removeRecentSearch(q),
            ),
          ),
      ],
    );
  }

  void _removeRecentSearch(String query) {
    final storage = KeyStorage();
    _recentSearches.remove(query);
    storage.write(key: 'recent_searches', value: jsonEncode(_recentSearches));
    setState(() {});
  }

  String _modeLabel(SearchMode mode) {
    switch (mode) {
      case SearchMode.people:
        return 'Kişiler';
      case SearchMode.hashtags:
        return 'Hashtag';
      case SearchMode.posts:
        return 'Gönderiler';
    }
  }
}

enum SearchMode { people, hashtags, posts }

class SearchResult {
  const SearchResult._({
    required this.type,
    this.profile,
    this.hashtag,
    this.hashtagSample,
    this.post,
  });

  final SearchResultType type;
  final ProfileView? profile;
  final String? hashtag;
  final NostrEvent? hashtagSample;
  final NostrEvent? post;

  factory SearchResult.profileResult(ProfileView p) => SearchResult._(
        type: SearchResultType.profile,
        profile: p,
      );

  factory SearchResult.hashtagResult(String tag, NostrEvent sample) => SearchResult._(
        type: SearchResultType.hashtag,
        hashtag: tag,
        hashtagSample: sample,
      );

  factory SearchResult.postResult(NostrEvent p) => SearchResult._(
        type: SearchResultType.post,
        post: p,
      );
}

enum SearchResultType { profile, hashtag, post }

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;

    switch (result.type) {
      case SearchResultType.profile:
        final p = result.profile!;
        final isFollowing = session.isFollowing(p.pubkey);
        return ListTile(
          leading: Avatar(seed: p.pubkey, label: p.displayName, imageUrl: p.picture, size: 40),
          title: Text(p.displayName),
          subtitle: Text('@${p.pubkey.substring(0, 8)}…'),
          trailing: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              backgroundColor: isFollowing ? AppColors.surfaceAlt : null,
              foregroundColor: isFollowing ? AppColors.text : null,
              side: isFollowing ? const BorderSide(color: AppColors.lineStrong) : null,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await session.followPerson(p.pubkey);
              messenger.showSnackBar(SnackBar(
                content: Text(ok
                    ? (session.isFollowing(p.pubkey) ? 'Takipten çıkarılamadı' : 'Takip ediliyor')
                    : 'İşlem gönderilemedi'),
              ));
            },
            child: Text(isFollowing ? 'Takip ediliyor' : 'Takip et'),
          ),
          onTap: () => showUserSheet(context, p.pubkey),
        );

      case SearchResultType.hashtag:
        return ListTile(
          leading: const Icon(Icons.tag, color: AppColors.accent, size: 28),
          title: Text('#${result.hashtag}'),
          subtitle: result.hashtagSample != null
              ? Text(
                  result.hashtagSample!.content.length > 80
                      ? '${result.hashtagSample!.content.substring(0, 80)}…'
                      : result.hashtagSample!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () {
            // Navigate to hashtag feed
            _openHashtagFeed(context, result.hashtag!);
          },
        );

      case SearchResultType.post:
        return PostTile(event: result.post!);
    }
  }

  void _openHashtagFeed(BuildContext context, String tag) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => HashtagFeedPage(tag: tag),
    ));
  }
}

/// Hashtag feed page (placeholder - full implementation needed)
class HashtagFeedPage extends StatelessWidget {
  const HashtagFeedPage({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('#$tag')),
      body: const Center(child: Text('Hashtag akışı - yakında')),
    );
  }
}