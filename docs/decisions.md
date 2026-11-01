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
