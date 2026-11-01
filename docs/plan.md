# Ana Plan

## 1. Ürün

Arkadaş çevresine açık, davetle girilen bir sosyal ağ:

- Metin + görsel gönderi, kronolojik akış
- Beğeni, yorum, profil, takip
- Birebir uçtan uca şifreli mesajlaşma
- Bildirimler (push)
- Engelleme / susturma

**Kapsam dışı (v1):** video, hikâye, algoritmik öneri, canlı yayın, grup sohbeti,
global keşif, web istemcisi.

## 2. Temel Kararlar

| Konu | Karar | Gerekçe |
|---|---|---|
| İstemci | Flutter | Nostr/push/keystore ekosistemi olgun |
| Protokol | Nostr | İmzalı event log + relay modeli hazır |
| Kimlik | Ed25519 (`nsec`/`npub`) | Sunucusuz, taşınabilir |
| Yerel depo | SQLite (`drift`) | Çevrimdışı okuma, hızlı akış |
| Relay | `strfry` (üretim), `nostr-rs-relay` (yerel) | Olgun, tek ikili |
| Medya | Cloudflare R2 | Ücretsiz katman, egress ücretsiz |
| Push | Gateway → FCM | Android'de tek yol |
| Domain | `<isim>.dpdns.org` | Ücretsiz, PSL'de, Cloudflare'e delege edilebilir |
| Hosting | Oracle Cloud free tier | 0 €, datacenter bant genişliği |
| Dağıtım | GitHub Releases | Play Store yok, sürüm kontrolü uygulama içi |
| Maliyet | **0 €/ay** | Domain, relay, medya, dağıtım hepsi ücretsiz katmanda |

## 3. Mimari Özet

```
Telefon (nsec + SQLite event store)
   │  imzalı event (WSS)
   ▼
Relay 1 (strfry, whitelist)  ⇄  Relay 2 (yedek)
   │
   ├──► Telefon B (abonelik, doğrulama, yerel yazma)
   ├──► Push gateway (npub → FCM token) ──► FCM
   └──► R2 (görseller, NIP-92 imeta)
```

Ayrıntı: [`architecture.md`](architecture.md)

## 4. Fazlar ve Takvim

Toplam **10 hafta** (tek kişi, yarı zamanlı). Ayrıntılı kabul kriterleri:
[`phases.md`](phases.md)

| Faz | Hafta | Konu |
|---|---|---|
| 1 | 0 | Temel altyapı + yerel test ortamı |
| 2 | 1–2 | Kimlik, yedekleme, davet |
| 3 | 3–4 | Profil, gönderi, medya |
| 4 | 5–6 | Akış, beğeni, yorum, engelleme |
| 5 | 7 | Birebir mesajlaşma |
| 6 | 8 | Push bildirim |
| 7 | 9–10 | Üretim, dağıtım, v1.0.0 |

## 5. Riskler ve Önlemler

| Risk | Etki | Önlem |
|---|---|---|
| `nsec` kaybı | Hesap kaybı | Zorunlu NIP-49 yedeği + QR, onboarding'de atlanamaz |
| Flutter Nostr paket olgunluğu | Geliştirme durması | `NostrClient` soyutlaması; gerekirse kendi minimal istemci |
| Ücretsiz domain kaybı | Kimlik/relay adresi değişir | NIP-65 relay listesi, NIP-05 yeniden yayın, EU.org yedek başvuru |
| Relay tek nokta | Kesinti | İki relay'a çift yayın, istemcide relay listesi |
| Silme garantisi yok | Gizlilik beklentisi | NIP-09 + kendi relay'ında zorunlu silme; kullanıcıya açıkça söylenir |
| Push gateway tek nokta | Bildirim gelmez | İnce servis; çökse uygulama çalışmaya devam eder |
| Android pil optimizasyonu | Bildirim gecikmesi | Kullanıcıya yönlendirme ekranı |
| Disk/enerji (yerel test) | Ortam bozulması | Tüm araçlar kullanıcı alanında, sudo gerektirmez |

## 6. Yasal / Hijyen

- Gizlilik metni: hangi veri cihazda, hangi veri relay'de, hangi veri push gateway'de.
- Hesap silme: `nsec` imhası + relay'e NIP-09 silme istekleri.
- Yaş sınırı: 13+ beyanı (davetli ağ olduğu için düşük risk).
- Play Store yok → Data Safety formu, mağaza denetimi yok.

## 7. Bilinçli Olarak Yapılmayanlar

- Mikroservis mimarisi (tek relay + tek gateway yeterli)
- Redis (tek örnekte gereksiz)
- Cloudflare Tunnel (relay public IP'de)
- CDN katmanı (R2 zaten edge'den servis ediyor)
- Video altyapısı
