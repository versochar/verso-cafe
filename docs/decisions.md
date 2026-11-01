# Kararlar (ADR)

Her karar: bağlam → karar → sonuç.

---

## ADR-001: İstemci Flutter
**Bağlam:** Android sosyal uygulama; Nostr, push, secure storage, medya ihtiyaçları var.
**Karar:** Flutter (Dart).
**Sonuç:** Olgun ekosistem, tek kod tabanı, iyi performans. Python istemci seçenekleri
(Kivy/BeeWare) push ve arka plan servislerinde kırılgan olduğu için reddedildi.

## ADR-002: Protokol Nostr
**Bağlam:** P2P isteniyor; veri kullanıcıda kalmalı.
**Karar:** Nostr (imzalı event log + relay).
**Sonuç:** Protokol yazma yükü yok. Relay değiştirilebilir. Bedeli: metadata gizliliği
yok, silme garantisi yok, anahtar kaybı telafi edilemez.

## ADR-003: Relay olarak strfry / nostr-rs-relay
**Bağlam:** Whitelist, düşük kaynak tüketimi, tek ikili kurulum.
**Karar:** Üretimde `strfry`, yerelde `nostr-rs-relay` (sudo gerektirmeyen kurulum).
**Sonuç:** İkisi de aynı protokolü konuşur; yerel geliştirme üretimi birebir taklit eder.

## ADR-004: Domain `*.dpdns.org`
**Bağlam:** Ücretsiz domain gerekiyor; Freenom kapandı; Cloudflare zone gerekiyor.
**Karar:** DigitalPlat `dpdns.org` (PSL'de, NS delegasyonu var).
**Sonuç:** 0 €. Risk: sağlayıcı politikası değişebilir → NIP-65 ile taşınabilirlik.
Yedek plan: EU.org başvurusu.

## ADR-005: Hosting Oracle Cloud free tier
**Bağlam:** Ev PC'si 7/24 açık kalmamalı; upload hızı düşük.
**Karar:** Oracle free tier VM.
**Sonuç:** 0 €, datacenter bant genişliği. Cloudflare Tunnel gereksiz.

## ADR-006: Medya Cloudflare R2
**Bağlam:** Düşük upload hızı; görseller evden/sunucudan geçmemeli.
**Karar:** Pre-signed PUT ile doğrudan R2'ye yükleme, okuma R2/CDN üzerinden.
**Sonuç:** Upload sorunu ortadan kalkar; 10 GB ücretsiz katman yeterli.

## ADR-007: Dağıtım GitHub Releases
**Bağlam:** Play Store kullanılmayacak, sadece arkadaşlara APK.
**Karar:** Public `-releases` reposu + `app.apk` + `version.json` asset'i.
**Sonuç:** Store ücreti/denetimi yok. Güncelleme uygulama içi kontrolle yapılır.
Alternatif (Firebase App Distribution) gereksiz sürtünme yaratıyor.

## ADR-008: Relay whitelist
**Bağlam:** Davetli ağ; spam ve istenmeyen içerik istemiyoruz.
**Karar:** Yalnızca onaylı `npub`'lar yazabilir; okuma da kapalı ağ.
**Sonuç:** Yönetim yükü düşük. Davet akışının uygulamada olması gerekir.

## ADR-009: DM için NIP-17
**Bağlam:** Birebir mesajlaşma; relay içeriği görmemeli.
**Karar:** NIP-17 gift wrap + NIP-44.
**Sonuç:** Metadata (zaman, taraflar) görünür ama içerik şifreli. Eski NIP-04 kullanılmaz.

## ADR-010: Python yalnızca yardımcı servislerde
**Bağlam:** Python tercihi var; ancak istemcide riski yüksek.
**Karar:** İstemci Flutter; push gateway istenirse Python (FastAPI) yazılabilir.
**Sonuç:** Dil tercihi korunur, riskli katmanlar olgun ekosistemde kalır.

## ADR-011: İsimlendirme (karara bağlandı — Verso Cafe)
**Bağlam:** Uygulama adı Faz 1'de kesinleşmemişti; geçici ad `Sosyal` kullanıldı.
**Karar:** 1 Kasım 2026'da kullanıcı adı **Verso Cafe** olarak kesinleştirdi.
Kullanıcıya görünen her yerde (launcher etiketi, akış başlığı, bildirim metinleri,
`AppConfig.name`, dokümanlar) bu ad kullanılır.
**Sonuç:** Teknik kimlikler bilinçli olarak `sosyal` kaldı: `applicationId`
`com.sosyal.app` (değiştirmek mevcut kurulumları ve Keystore kimliklerini sıfırlardı),
`sosyal.dpdns.org` alanı ve `~/.android/sosyal-release.keystore` imza anahtarı.
Yeni bir `applicationId` ancak sıfırdan kurulum yapılabilirse mantıklı olur.

## ADR-012: Sürüm kontrolü GitHub API'siz
**Bağlam:** Anonim GitHub API saatte 60 istekle sınırlı.
**Karar:** `releases/latest/download/version.json` doğrudan asset URL'i.
**Sonuç:** Rate limit yok, cache'lenebilir, uygulama içi kontrol basit.

## ADR-013: Hesaplar — Firebase Auth + Firestore, içerik yine Nostr'da
> **Durum: ADR-015 ile geçersiz kılındı.** Firebase/Google hesabı gerekmediği
> için hesaplar kendi sunucumuza taşındı; aşağıdaki metin tarihsel kayıttır.

**Bağlam:** Kullanıcı adı + parola girişi ve host/mod yetki sistemi istendi;
Nostr'da klasik parola kavramı yok (anahtar = kimlik).
**Karar:** Hibrit model. Kimlik katmanı Firebase'de: kullanıcı adı
`ad@hesap.verso.app` e-postasına eşlenir, kayıtta Nostr anahtar çifti üretilir ve
**NIP-49 ile kullanıcının parolasıyla şifrelenip** `users/{uid}` belgesinde
saklanır; girişte parola ile çözülür. Sunucuda düz anahtar/parola durmaz.
İçerik (gönderi/DM/fotoğraf) eskisi gibi relay + medya sunucusunda.
Roller `users/{uid}.role`: `host | mod | user`. Tohum host `hosthesap`
kural olarak Firestore güvenlik kurallarında tanımlıdır (yalnız o e-posta
host olarak doğabilir); sonraki tüm rol değişikliklerini yalnız mevcut host
yapar — hostluk devri de bir rol güncellemesidir. Duyurular
`announcements/{id}` koleksiyonunda; yazma yalnız host/mod.
**Sonuç:** Başka cihazda ad+parola ile anahtara dönülür. Firebase erişilemezse
yerel anahtarla kullanım sürer (AuthGate anahtarı Keystore'dan okur).
Kısıt: Firebase parola alt sınırı 6 karakterdir — 12345 gibi 5 haneli
parolalar kabul edilmez. Geliştirme/test Firebase Emulator Suite ile yapılır
(`infra/firebase/`, auth :9099, firestore :8188).

## ADR-014: Ağ adresleri çalışma zamanında `network.json`'dan
**Bağlam:** Relay/medya adresleri APK'ya derleme sırasında gömülüyordu. Ev
sunucusu tünelle (Cloudflare) dışarı açıldığında adres tünel yeniden başlayınca
değişiyor; her değişimde yeni APK yayınlamak hem yavaş hem de arkadaşları her
seferinde güncellemeye zorluyor.
**Karar:** Uygulama açılışta `network.json`'u okur
(`raw.githubusercontent.com/versochar/verso-cafe/main/network.json`) ve
`relay`/`media`/`account` alanları gömülü adreslerin üzerine yazar. Doğrulanan
değer cihazda saklanır (Keystore), böylece çevrimdışı açılışta son bilinen
adres kullanılır. Adres değişince tek komut yeter: `scripts/publish-network.sh`.
**Güvenlik:** Yalnız `wss://` / `https://` kabul edilir; `ws://` / `http://`
yalnız yerel geliştirme adreslerinde (127.0.0.1, localhost, 10.0.2.2). Böylece
uzaktan gelen bir yapılandırma uygulamayı cleartext'e düşüremez. Dosya HTTPS ve
depo üzerinden gelir; TLS araya girmeyi engeller.
**Sonuç:** Tünel adresi değişince APK yayınlanmaz; arkadaşların uygulaması bir
sonraki açılışta yeni adrese geçer. Kalıcı bir adres (Cloudflare named tunnel,
VPS) seçilirse aynı mekanizma sunucu taşımayı da kolaylaştırır.

## ADR-015: Hesaplar kendi sunucumuzda — sıfır dış bağımlılık
**Bağlam:** ADR-013 hesapları Firebase'e bağlamıştı. Firebase projesi açmak,
`google-services.json` üretmek ve Google hesabı yönetmek istemedik; ayrıca
kullanıcı "sunucu tamamen benim bilgisayarımda olsun" dedi. Arkadaş çemberi
küçük: birkaç on hesap, günde birkaç yüz istek.
**Karar:** `apps/account-server` — yalnız `dart:io` + `crypto` ile yazılmış,
ev bilgisayarında çalışan hesap servisi. Kullanıcı adı + parola, roller ve
duyurular burada; gönderi/DM/fotoğraf yine Nostr relay + medya sunucusunda.
- Parola asla düz saklanmaz: PBKDF2-HMAC-SHA256, kullanıcıya özel tuz,
  60.000 tur. Oturum jetonu rastgele üretilir, sunucuda yalnız sha256 özeti
  tutulur; 30 gün geçerli, çıkışta iptal edilir.
- Nostr anahtarı sunucuda düz durmaz: istemci NIP-49 ile parolayla şifreler,
  sunucu yalnız `ncryptsec` paketini saklar. Girişte istemci çözer.
- Roller: tohum host `hosthesap` (ilk kayıt); host mod/user atar, hostluğu
  devreder. Duyuruyu yalnız host/mod yazar, yalnız host siler.
- Depo: `${ACCOUNT_DB:-$HOME/sosyal-accounts/accounts.json}`; yazma atomik
  (tmp + rename). Sunucu dışarıya yalnız Cloudflare tüneliyle açılır.
- Kötüye kullanım: aynı kullanıcı adında 10 dakikada 8 başarısız girişten
  sonra 429 (bellekte; yeniden başlatınca sıfırlanır).
**Sonuç:** Google/Firebase hesabı, emülatör ve `google-services.json` gerekmez;
sunucu `./scripts/serve.sh` ile ayağa kalkar. Adres `network.json` → `account`
alanından gelir (ADR-014). Kısıt: sunucu kapalıysa yeni giriş/kayıt yapılamaz;
cihazdaki mevcut anahtarla uygulama çalışmaya devam eder. Yedek: JSON dosyasını
kopyalamak yeterli (parolalar PBKDF2, anahtarlar NIP-49 ile şifreli).
