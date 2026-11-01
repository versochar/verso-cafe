# Mimari

## 1. Bileşenler

| Bileşen | Sorumluluk | Nerede |
|---|---|---|
| İstemci (Flutter) | UI, anahtar, imzalama, yerel depo, ağ | Kullanıcı telefonu |
| Relay | Event saklama ve dağıtımı (aptal kutu) | Oracle VM |
| Push gateway | Relay → FCM köprüsü | Oracle VM |
| Medya | Görsel saklama/servis | Cloudflare R2 |
| Dağıtım | APK + sürüm bilgisi | GitHub Releases |

## 2. Veri Akışı

### Gönderi yayınlama
```
kullanıcı yazar
  → yerel SQLite'a taslak
  → secp256k1 ile imzala (nsec cihazda)
  → relay 1'e EVENT, relay 2'ye EVENT
  → OK alınınca "gönderildi" durumu
```

### Akış okuma
```
açılış → yerel cache'ten göster (anında)
       → relay'e REQ (authors = takip listesi, limit)
       → gelen event'ler: imza doğrula → SQLite'a yaz → UI güncelle
```

### Görsel yükleme
```
POST /media/upload-url (gateway veya statik imzalayıcı)
  → pre-signed PUT → R2
  → note içine NIP-92 imeta etiketi
```

## 3. Kullanılan NIP'ler

| NIP | Kullanım |
|---|---|
| 01 | Event yapısı, imza, filtreler |
| 02 | Takip listesi (`kind:3`) |
| 09 | Silme isteği (`kind:5`) |
| 10 | Yorum/thread etiketleri |
| 17 | Birebir DM (gift wrap) |
| 19 | `bech32` kodlama (`npub`/`nsec`/`note`) |
| 42 | Relay kimlik doğrulama (whitelist) |
| 44 | DM şifreleme |
| 49 | Şifreli anahtar dışa aktarma (`ncryptsec`) |
| 51 | Susturma/engelleme listeleri |
| 65 | Relay listesi |
| 92 | Gönderi içi medya (`imeta`) |

## 4. Event Türleri

| Kind | İçerik | Kalıcı mı |
|---|---|---|
| 0 | Profil metadata | Son hali geçerli |
| 1 | Gönderi / yorum | Append-only |
| 3 | Takip listesi | Son hali geçerli |
| 5 | Silme isteği | Append-only |
| 7 | Beğeni | Append-only |
| 1059 | Gift wrap (DM) | Append-only |
| 10000 | Susturma listesi | Son hali geçerli |
| 10002 | Relay listesi | Son hali geçerli |

## 5. Yerel Veri Modeli (SQLite)

```
events(id TEXT PK, kind INT, pubkey TEXT, created_at INT, content TEXT,
       tags TEXT, sig TEXT, raw TEXT, received_at INT)
profiles(pubkey TEXT PK, name, about, picture, updated_at)
follows(pubkey TEXT PK, relay_hint, added_at)
timelines(name TEXT, event_id TEXT, position INT)
outbox(id INTEGER PK, event_raw TEXT, attempts INT, last_error TEXT)
relay_status(url TEXT PK, connected INT, last_ok INT, last_error TEXT)
```

Kurallar:
- `events` append-only; aynı `id` tekrar gelirse yoksayılır.
- `kind:0/3/10000/10002` için "en yeni `created_at` kazanır".
- Silme: `kind:5` hedef `e` etiketlerini işaretler, UI'da gizlenir.

## 6. Anahtar Yönetimi

- `nsec` yalnızca `flutter_secure_storage` (Android Keystore) içinde.
- Bellekte tutulan süre minimum; loglara asla yazılmaz.
- Yedek: NIP-49 `ncryptsec` + QR. Onboarding'de doğrulama adımı zorunlu.
- Çoklu cihaz (v2): NIP-46 remote signer.

## 7. Relay Topolojisi

- **Birincil:** `strfry`, whitelist + NIP-42 AUTH.
- **Yedek:** ikinci host, `strfry router` ile çift yönlü senkron.
- İstemci her eventi ikisine de yayınlar, ilk `OK` yeterli.
- Relay listesi `kind:10002` ile yayınlanır → domain/relay değişimi istemci tarafında şeffaf.

## 8. Güvenlik Notları

- Whitelist olmadan relay spam'e açılır; davet listesi zorunlu.
- DM içeriği relay'de şifreli; metadata (kim, kime, ne zaman) görünür.
- Push gateway yalnızca "yeni event var" bilgisi taşır, içerik taşımaz.
- Medya URL'leri tahmin edilemez (hash'li); private gönderi v1'de yok.
- `nsec` kaybı = hesap kaybı; kurtarma yok (protokol gereği).
