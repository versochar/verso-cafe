# Arayüz (UI) — Tasarım Sistemi

Bu belge Verso Cafe'nin görsel dilini ve ekran yapısını tanımlar. Düzen mantığı
Instagram'dan ilham alır (hikâye sırası, tam genişlik kart, 3 sütunlu ızgara,
ortada oluştur butonu) ama renk, tipografi ve içerik türü bize aittir.

## Tasarım ilkeleri

1. **Tek vurgu rengi.** Arayüz nötr koyu yüzeylerden oluşur; turuncu
   (`#FF6B35`) yalnızca birincil eylem, seçili durum ve bağlantı noktası için
   kullanılır.
2. **Gölge yerine çizgi.** Kartlar gölge ile değil, 1px `#232327` çerçeve ile
   ayrılır. Akışta gönderiler arası ayrım olarak 6px'lik koyu bant kullanılır.
3. **4pt boşluk ölçeği.** Tüm boşluklar `Insets` sabitlerinden gelir.
4. **Tek yazı ölçeği.** `AppTheme.dark` içindeki `TextTheme` tek kaynaktır.
5. **Sessiz boş durumlar.** Boş liste yönlendirici bir `EmptyState` ile gösterilir.

## Dosya yapısı

```
lib/
├── ui/
│   ├── theme.dart      # renk, boşluk, yarıçap, ThemeData
│   ├── widgets.dart    # Surface, Avatar, StoryItem, EmptyState, PageHeader…
│   └── format.dart     # relativeTime, feedTime, clockTime, shortNpub
├── core/session/
│   └── app_session.dart  # tek WebSocket, kimlik, not/yorum/beğeni/takip önbelleği
└── features/
    ├── shell/home_shell.dart       # 5 yuvalı alt bar + IndexedStack
    ├── feed/                       # akış, hikâye sırası, kart, besteci, kullanıcı sheet'i
    ├── notifications/              # bildirim merkezi (zil sheet'i)
    ├── explore/explore_page.dart   # arama + kişi şeridi + 3'lü gönderi ızgarası
    ├── dm/                         # sohbet listesi + sohbet ekranı
    └── profile/                    # profil başlığı, istatistikler, ızgara, ayarlar
```

## Renk paleti

| Token | Değer | Kullanım |
|---|---|---|
| `background` | `#0A0A0B` | sayfa zemini |
| `surface` | `#121214` | kart, giriş alanı, ızgara karesi |
| `surfaceAlt` | `#18181B` | ikincil buton, karşı mesaj balonu |
| `line` | `#232327` | ayırıcı, kart çerçevesi |
| `lineStrong` | `#313136` | odaklı giriş, güçlü çerçeve |
| `text` | `#F4F4F5` | birincil metin |
| `textMuted` | `#8D8D95` | ikincil metin |
| `textFaint` | `#5F5F67` | ipucu, ikon |
| `accent` | `#FF6B35` | birincil eylem, beğeni, halka |
| `online` | `#4ADE80` | bağlı durumu |

## Ekranlar

### Alt gezinme (`HomeShell`)
Beş yuva: **Akış · Keşfet · (+) Paylaş · Mesajlar · Profil**. Ortadaki `+`
sekme değiştirmez, besteciyi açar. Profil yuvası kişinin kendi avatarını
gösterir; seçiliyken turuncu halka alır. İçerik `IndexedStack`'te durur.

### Akış
- Üstte "Verso Cafe" yazısı + **zil** + bağlantı durumu. Zildeki
  turuncu rozet okunmamış bildirim sayısını gösterir (`9+`'a kadar).
- **Hikâye sırası:** son gönderi yazarları. İlk halka "Sen" (+ rozetli,
  dokununca besteci açılır). Aktif olmayan halka gri, aktif turuncu–pembe
  degradeli çerçeve alır. Halkaya dokunmak o kişinin özet sheet'ini açar.
- **Gönderi kartı (tam genişlik):** avatar + ad + `SEN` rozeti + `2 SA ÖNCE`
  + `···` menüsü; gövde; eylem satırı (kalp, yorum, yeniden gönder, yer imi);
  `N beğeni · N yeniden gönderim`; ≤2 yorum satırda, fazlaysa "Tüm N yorumu gör".
- **Yeniden gönderme (NIP-18, `kind:6`):** kart, akışın tepesinde üstünde
  `X yeniden gönderdi · ZAMAN` şeridiyle belirir; aynı gönderi şeritsiz
  bir daha listelenmez (tek kopya kuralı).
- Beğeni/yorum/yeniden gönderim relay event'lerinden (`kind:7` / `kind:10` /
  `kind:6`) hesaplanır. Yer imi yalnızca cihazda tutulur.

### Keşfet
- Arama kutusu: ada göre filtreler; `npub1…` girilirse bech32 çözümlenir.
- **İnsanlar** şeridi: avatar + ad, dokununca kullanıcı sheet'i.
- **Gönderiler:** 3 sütunlu, 2px aralıklı kare ızgara; kareler yazar
  renginden türeyen degrade taşır, dokununca gönderi detayı açılır.

### Kullanıcı sheet'i (`showUserSheet`)
Büyük avatar, ad, `npub`, bio, `N gönderi · N takip · N takipçi`,
kişi siz değilseniz **Takip et / Takip ediliyor** (`kind:3` yazar) ve
**Mesaj** düğmesi, sonra kişinin gönderileri.

### Gönderi detayı (`showPostSheet`)
Sürüklenebilir sheet: kartın tam hali + tüm yorumlar (avatar, ad, içerik, zaman).

### Bildirim merkezi (`showNotificationsSheet`)
Zilden açılır; kendi gönderilerine yönelen `kind:7` beğeni, `kind:10` yorum
ve `kind:6` yeniden gönderimleri kronolojik listeler. Her satır: avatar
(üzerinde eylem ikonu rozeti), "X gönderini beğendi / yorum yaptı / yeniden
gönderdi", alıntı (yorum metni ya da gönderi ilk satırı) ve göreli zaman.
Okundu zamanı (`notif_read_at`) Keystore'da saklanır; sheet açılınca rozet
sıfırlanır, açılış anından sonraki kayıtlar turuncu nokta taşır.

### Engelleme (NIP-10, `kind:10000`)
- Karttaki `···` menüsü ve kullanıcı sheet'i, engelle / engeli kaldır
  düğmesi içerir; engelleme replaceable `kind:10000` olarak yayınlanır.
- Engellenenlerin gönderileri akıştan, keşfet ızgarasından, hikâye sırasından
  ve kişi aramasından düşer; kendi gönderimizdeki yorum alıntıları kalır.
- Profil → Ayarlar → **Gizlilik → Engellenenler**: liste; satıra dokunmak
  engeli kaldırır ve sayaç canlı güncellenir.

### Mesajlar / Sohbet — gerçek NIP-44
`kind:1059` gift-wrap içeriği artık simülasyon değil: secp256k1 ECDH +
HKDF + ChaCha20 + HMAC-SHA256 (`lib/core/nostr/nip44.dart`, resmi
`nip44.vectors.json` vektörleriyle testli). Konuşma anahtarı simetriktir;
çözülemeyen eski yükler "Şifreli mesaj" olarak görünür.

### Profil
- Üstte kullanıcı adı (`ad_soyad` biçiminde) + ayarlar dişlisi.
- Büyük avatar (halkalı) + yanında **Gönderi / Takip / Takipçi** sayıları.
  Takip sayısı kişinin `kind:3` listesinden, takipçi sayısı başkalarının
  `kind:3` listelerinden hesaplanır.
- Ad, `npub` (kopyalar), bio; yanında **Profili düzenle** ve **Davet et**.
- Kendi gönderileri 3 sütunlu ızgara; kalp rozeti beğeni sayısını gösterir;
  dokununca detay sheet'i.

## Açılış davranışı

`main()` arayüzü hemen çizer; kimlik ve relay bağlantısı `AppSession.init()`
içinde arka planda yüklenir. Android açılış ekranı `#0A0A0B`'dir.

## Ekran görüntüleri

| Dosya | Ekran |
|---|---|
| `docs/img/ui-feed.png` | Akış: hikâye sırası + gönderi kartı |
| `docs/img/ui-explore.png` | Keşfet: kişiler + gönderi ızgarası |
| `docs/img/ui-compose.png` | Ortak `+` ile açılan besteci |
| `docs/img/ui-user.png` | Kullanıcı sheet'i |
| `docs/img/ui-post-detail.png` | Gönderi detayı + yorumlar |
| `docs/img/ui-profile.png` | Profil (başlık + ızgara) |
| `docs/img/ui-messages.png` | Mesajlar |
| `docs/img/ui-chat.png` | Sohbet balonları |
| `docs/img/ui-backup.png` | NIP-49 yedekleme diyaloğu |
| `docs/img/ui-repost.png` | Yeniden gönderim şeridi + `N yeniden gönderim` sayacı |
| `docs/img/ui-notifications.png` | Bildirim merkezi (zil sheet'i) |
| `docs/img/ui-dm-nip44.png` | Gerçek NIP-44 çözülmüş sohbet |
| `docs/img/ui-blocked.png` | Ayarlar → Engellenenler |
| `docs/img/ui-background-setting.png` | Ayarlar → Arka plan bağlantısı anahtarı |
| `docs/img/ui-bg-notifications.png` | Uygulama kapalıyken gelen bildirimler |
| `docs/img/ui-photo-compose.png` | Besteci: galeriden seçilen görsel önizlemesi |
| `docs/img/ui-photo-post.png` | Akışta fotoğraflı gönderi |
| `docs/img/ui-qr-scan.png` | QR taraması sonrası açılan kullanıcı sheet'i |

## Fotoğraflı gönderi (kendi medya sunucun)

- **Sunucu:** `apps/media-server` — tek dosya Dart (`dart run bin/server.dart`),
  `POST /upload` yalnızca **NIP-98** (`kind:27235`) imzalı başlıkla, `GET /m/<ad>`
  sha256 adlı dosyaları `immutable` cache ile servis eder. Depo: `~/sosyal-media`.
  Betikler: `scripts/media-server-start.sh` / `-stop.sh`.
- **İstemci:** bestecideki 📷 düğmesi galeriden seçer (`image_picker`, 2048px/k82
  sıkıştırma), `MediaUploader` yükler, adres gönderiye **NIP-92 `imeta`** etiketi
  olarak gömülür. Akış, gönderi detayı, profil ve keşfet ızgarası `imeta`'daki
  görseli basar.
- **Adres:** `--dart-define=MEDIA_URL=http://192.168.1.109:8080`
- Uçtan uca doğrulandı: cihaz galeriden seçti → NIP-98 imzalı yüklemeyim sunucuya
  düştü → `imeta`'lı gönderi akışta görseliyle göründü (`docs/img/ui-photo-post.png`).

## Arka plan bağlantısı

Ayarlar → Bağlantı → **Arka plan bağlantısı** anahtarı, uygulama kapalıyken
`flutter_foreground_task` ön plan servisini çalıştırır:

- Görev izole edicisi saf Dart `RelayClient` ile relay'e bağlanır ve yalnızca
  bana yönelen olayları abone olur (`kind:7/6/10` p=ben, `kind:1059` p=ben).
- Yeni olaylar `flutter_local_notifications` ile Android bildirimi olur; DM
  içeriği görev izole edicisinde NIP-44 ile çözülerek önizlenir.
- Bildirimler zil'deki okuma zamanını (`notif_read_at`) paylaştığı için
  okunmuş etkinlik yeniden bildirilmez.
- Tercih Keystore'da (`bg_watch`) tutulur; uygulama açılışta `restore()` ile
  servisi ayağa kaldırır. Sistem servisi düşürürse Android yeniden başlatır
  (emülatörde `kill -9` sonrası ~8 sn içinde doğrulandı).
- Gerekli Android tarafı: `<service android:foregroundServiceType="dataSync|remoteMessaging">`
  bildirimi + `SosyalTaskListener` (görev engine'ine `GeneratedPluginRegistrant`
  kaydeder; aksi halde bildirim eklentisi izole edicide bulunamaz).
