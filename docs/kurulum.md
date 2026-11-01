# Verso Cafe — Kurulum (arkadaşlar için)

Verso Cafe davetliye kapalı, reklamsız bir arkadaş çemberi uygulamasıdır.
Sunucu ev bilgisayarında çalışır; içerik orada durur, reklam/izleme yoktur.

## 1. APK'yı indir

[Son sürüm](https://github.com/versochar/verso-cafe/releases/latest) sayfasından
telefonuna uygun dosyayı indir:

| Dosya | Kimler için |
|---|---|
| `verso-cafe-release-arm64.apk` | Yeni telefonların çoğu (2017 sonrası) |
| `verso-cafe-release-armv7.apk` | Eski/ucuz telefonlar |

Emin değilsen **arm64** ile başla; "uygulama yüklenemedi" derse armv7'yi kur.
Android "bilinmeyen kaynaklara izin ver" diye sorarsa izin ver (APK imzalıdır,
Play Store dışından kurulduğu için bu uyarı normaldir).

## 2. İlk açılış

- **Şimdilik:** "Yerel anahtarla devam et" → uygulama sana özel bir kimlik
  (anahtar) üretir. Profil → **Profili düzenle** ile adını yaz.
- **Hesaplar (kullanıcı adı + parola)** yakında açılacak; o zaman aynı ekrandan
  kayıt olacaksın. Parola en az **6 karakter** olmalı.

## 3. Arkadaş ekle

- **Sen:** Profil → **Davet et** → QR kodu göster.
- **Arkadaşın:** Keşfet → QR oku (ya da `npub1…` adresini yapıştır).
- Karşılıklı eklemek en sağlıklısı: sen onu, o seni.

## 4. Kullan

- **Akış:** gönderi, fotoğraf, beğeni, yorum.
- **Mesajlar:** uçtan uca şifreli birebir sohbet.
- **Bildirim:** uygulama kapalıyken de gelir (arka plan bağlantısı açıkken).

## 5. Güncellemeler

Yeni sürüm çıkınca uygulama **kendi indirir**; tek yaptığın "Kur"a basmak
(Android'in güvenlik kuralı). İlk kurulumu bir kez elle yaptıktan sonra
güncellemeler böyle gelir.

> **Not:** Sunucu ev bilgisayarında çalıştığı için o bilgisayar kapalıyken
> uygulama "Bağlı değil" der; açılınca kendiliğinden bağlanır.
