/// Kullanıcı hesapları — Firebase Auth + Firestore köprüsü.
///
/// Model: giriş kimliği Firebase (kullanıcı adı + parola), Nostr anahtarları
/// NIP-49 ile parolayla şifrelenip `users/{uid}` belgesinde durur. Böylece
/// kullanıcı başka bir telefonda aynı ad/parola ile girince anahtarlarına
/// kavuşur; sunucuda düz anahtar ya da parola saklanmaz.
///
/// Roller: `host` (tek yetkili; devredebilir), `mod` (duyuru yazar),
/// `user` (normal). Koleksiyon boşken açılan ilk hesap host olur.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';
import '../nostr/keys.dart';
import '../nostr/nip49.dart';

enum AccountRole { host, mod, user, anon;

  static AccountRole parse(Object? v) => switch (v?.toString()) {
        'host' => AccountRole.host,
        'mod' => AccountRole.mod,
        _ => AccountRole.user,
      };

  String get labelTR => switch (this) {
        AccountRole.host => 'Host',
        AccountRole.mod => 'Mod',
        AccountRole.user => 'Üye',
        AccountRole.anon => 'Misafir',
      };
}

class Account {
  const Account({
    required this.uid,
    required this.username,
    required this.role,
    required this.pubkey,
  });

  final String uid;
  final String username;
  final AccountRole role;
  final String pubkey;

  bool get isHost => role == AccountRole.host;
  bool get canAnnounce => role == AccountRole.host || role == AccountRole.mod;

  static Account fromDoc(String uid, Map<String, dynamic> data) => Account(
        uid: uid,
        username: data['username']?.toString() ?? uid,
        role: AccountRole.parse(data['role']),
        pubkey: data['pubkey']?.toString() ?? '',
      );
}

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Kullanıcı adı → Firebase e-postası. Görünürde kullanıcı adı yazılır;
/// Firebase zorunlu e-posta alanı iç alt alanıyla üretilir.
String emailForUsername(String username) =>
    '${username.toLowerCase().trim()}@hesap.verso.app';

final RegExp usernamePattern = RegExp(r'^[a-z0-9_.]{3,32}$');

class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  // Firebase erişimi tembel: yapılandırılmamışsa (yer tutucu
  // google-services.json) singleton oluşurken çökmek yerine çağrı anında
  // hata verir; çağıranlar bunu yakalar ve yerel anahtarla devam eder.
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Account? _account;
  Account? get account => _account;
  User? get authUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  bool get signedIn => authUser != null;

  /// Ana isola açılışında bir kez; emülatör ayarlarını uygular.
  static Future<void> configure() async {
    if (AppConfig.firebaseEmulatorHost.isNotEmpty) {
      await FirebaseAuth.instance
          .useAuthEmulator(AppConfig.firebaseEmulatorHost, 9099);
      FirebaseFirestore.instance
          .useFirestoreEmulator(AppConfig.firebaseEmulatorHost, 8188);
    }
  }

  /// Zaten açık oturumu yükler; yoksa `null`.
  Future<Account?> restore() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final snap = await _db.collection('users').doc(user.uid).get();
    final data = snap.data();
    if (data == null) return null;
    return _account = Account.fromDoc(user.uid, data);
  }

  /// Yeni hesap: Firebase kaydı + Nostr anahtarı üretimi + NIP-49 yedeği.
  /// Anahtar döner; çağırıcı Keystore'a yazıp oturumu başlatır.
  Future<({Account account, KeyPair keys})> register(
      String username, String password) async {
    final name = username.toLowerCase().trim();
    if (!usernamePattern.hasMatch(name)) {
      throw const AccountException(
          'Kullanıcı adı 3-32 karakter olmalı: küçük harf, rakam, _ veya .');
    }
    if (password.length < 6) {
      throw const AccountException('Parola en az 6 karakter olmalı.');
    }

    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
          email: emailForUsername(name), password: password);
    } on FirebaseAuthException catch (e) {
      throw AccountException(_authError(e));
    }
    final uid = cred.user!.uid;

    final keys = KeyPair.generate();
    final ncryptsec = await Nip49.encrypt(keys.privateKeyHex, password);

    // Tohum host kuralı (firestore.rules): host olarak doğabilen tek hesap
    // hosthesap'ındır. Başkası boş koleksiyona rağmen "user" doğar.
    final seedHost = name == 'hosthesap';
    final account = Account(
      uid: uid,
      username: name,
      role: seedHost ? AccountRole.host : AccountRole.user,
      pubkey: keys.publicKeyHex,
    );
    await _db.collection('users').doc(uid).set({
      'username': name,
      'role': account.role.name,
      'pubkey': keys.publicKeyHex,
      'npub': keys.npub,
      'ncryptsec': ncryptsec,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return (account: _account = account, keys: keys);
  }

  /// Giriş: parolayla anahtarı çözer. Hata mesajları kullanıcıya gösterilir.
  Future<({Account account, KeyPair keys})> signIn(
      String username, String password) async {
    UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(
          email: emailForUsername(username), password: password);
    } on FirebaseAuthException catch (e) {
      throw AccountException(_authError(e));
    }
    final uid = cred.user!.uid;
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data();
    if (data == null) {
      throw const AccountException('Bu hesaba ait kayıt bulunamadı.');
    }
    final account = Account.fromDoc(uid, data);
    final KeyPair keys;
    try {
      final hex = await Nip49.decrypt(
          data['ncryptsec'] as String, password);
      keys = KeyPair.fromPrivateHex(hex);
    } catch (_) {
      throw const AccountException(
          'Anahtar çözülemedi — hesap başka bir parolayla mı şifrelendi?');
    }
    return (account: _account = account, keys: keys);
  }

  Future<void> signOut() async {
    _account = null;
    try {
      await _auth.signOut();
    } catch (_) {
      // Firebase yok/erişilemez: yerel anahtar silinerek oturum yine kapanır.
    }
  }

  // ------------------------------------------------------ yönetim (host)

  /// Host: tüm hesaplar (rol ekranı listesi).
  Future<List<Account>> listUsers() async {
    final snap = await _db.collection('users').get();
    final list = snap.docs
        .map((d) => Account.fromDoc(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.username.compareTo(b.username));
    return list;
  }

  /// Host: rol atar. Hostluk devri = hedefe host ver, kendine user/mod ver.
  Future<void> setRole(String uid, AccountRole role) =>
      _db.collection('users').doc(uid).update({'role': role.name});

  /// Hostluğu devret: hedef host olur, sen verilen role düşersin.
  Future<void> transferHost(String targetUid,
      {AccountRole selfRole = AccountRole.user}) async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(targetUid), {'role': 'host'});
    if (_account != null) {
      batch.update(_db.collection('users').doc(_account!.uid),
          {'role': selfRole.name});
    }
    await batch.commit();
    await restore();
  }

  /// Parola değişimi: anahtarı yeni parolayla yeniden sar.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null || _account == null) {
      throw const AccountException('Oturum açık değil.');
    }
    final snap = await _db.collection('users').doc(user.uid).get();
    final data = snap.data() ?? const {};
    String hex;
    try {
      hex = await Nip49.decrypt(data['ncryptsec'] as String, oldPassword);
    } catch (_) {
      throw const AccountException('Mevcut parola yanlış.');
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AccountException(_authError(e));
    }
    final fresh = await Nip49.encrypt(hex, newPassword);
    await _db.collection('users').doc(user.uid).update({'ncryptsec': fresh});
  }

  static String _authError(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' || 'user-not-found' || 'wrong-password' ||
        'invalid-credential' =>
          'Kullanıcı adı ya da parola hatalı.',
        'email-already-in-use' => 'Bu kullanıcı adı zaten kayıtlı.',
        'weak-password' => 'Parola çok zayıf (en az 6 karakter gerekir).',
        'too-many-requests' => 'Çok deneme — biraz sonra tekrar dene.',
        'network-request-failed' =>
          'Firebase bağlantısı kurulamadı (internet/ağ).',
        'operation-not-allowed' =>
          'Firebase konsolunda E-posta/Parola girişi açık değil.',
        _ => 'Firebase hatası: ${e.code}',
      };
}

/// Giriş/kayıt hatalarını kullanıcıya anlaşılır metne çevirir.
///
/// Firebase hiç yapılandırılmamışsa (yer tutucu `google-services.json`)
/// fırlatılan istisna teknik metin taşır; kullanıcıya yol gösterilir.
String accountErrorText(Object error) {
  if (error is AccountException) return error.message;
  final text = error.toString();
  if (text.contains('No Firebase App') || text.contains('FirebaseApp')) {
    return 'Hesaplar şu an kullanılamıyor (sunucu ayarlanmamış). '
        'Alttaki "Yerel anahtarla devam et" ile kullanabilirsin.';
  }
  if (error is FirebaseException) {
    return 'Firebase hatası: ${error.code}';
  }
  return 'Beklenmeyen hata: $error';
}

// ------------------------------------------------------------------ duyurular

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.authorName,
    required this.authorUid,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final String body;
  final String authorName;
  final String authorUid;
  final int createdAtMs;

  static Announcement fromDoc(
      DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const {};
    int ms;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      ms = raw.millisecondsSinceEpoch;
    } else if (raw is String) {
      ms = DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
    } else {
      ms = (raw as num?)?.toInt() ?? 0;
    }
    return Announcement(
      id: d.id,
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      authorName: data['authorName']?.toString() ?? '',
      authorUid: data['authorUid']?.toString() ?? '',
      createdAtMs: ms,
    );
  }

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
}

class AnnouncementService {
  AnnouncementService._();
  static final AnnouncementService instance = AnnouncementService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Canlı akış — en yeni üstte.
  Stream<List<Announcement>> watch({int limit = 50}) =>
      _db.collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(Announcement.fromDoc).toList());

  Future<void> post({required String title, required String body}) async {
    final me = AccountService.instance.account;
    if (me == null || !me.canAnnounce) {
      throw const AccountException('Duyuru yazma yetkin yok.');
    }
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty && b.isEmpty) {
      throw const AccountException('Boş duyuru gönderilmez.');
    }
    await _db.collection('announcements').add({
      'title': t.isEmpty ? 'Duyuru' : t,
      'body': b,
      'authorUid': me.uid,
      'authorName': me.username,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) =>
      _db.collection('announcements').doc(id).delete();
}
