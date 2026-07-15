# Order Risk Engine

A portfolio project that simulates a real SAP ABAP application: a BAdI-driven
risk scoring engine that evaluates every sales order at the moment it's
saved, running it through 7 weighted checks, blocking the most dangerous
ones outright, e-mailing management about the rest, and writing every single
evaluation to an audit log. Built with Object-Oriented ABAP.

> Mock data stands in for live database access here (`KNKK`/`BSID` for
> credit and payment, `VBAK`/`VBAP`/`KONV` for order and pricing data,
> `MARD` for stock, plus the three Z-tables this project defines). Every
> mock block has the real `SELECT`/`INSERT` written as a comment directly
> above it, so swapping in live tables later is a matter of deleting the
> mock and uncommenting the SQL — more on that in
> [docs/architecture.md](docs/architecture.md).

## Business scenario

Most sales orders are fine, but some carry real risk — a customer over
their credit limit, a chronic late payer, an order far bigger than that
customer has ever placed, stock that isn't really there, a blacklisted
customer/material pair, a discount way outside policy. None of that trips a
hard stop in the standard order flow today, and by the time someone
notices, the order has usually already shipped. This engine closes that gap
by scoring every order automatically the instant it's saved, instead of
relying on different teams each holding one piece of the picture.

Full write-up: [docs/business-scenario.md](docs/business-scenario.md)

## What it does

- Runs automatically the moment a sales order is saved, wired in through a
  BAdI — nobody has to remember to trigger a check.
- Scores the order across 7 weighted risk checks: credit limit, payment
  performance, order anomaly, stock, blacklist, price deviation, and
  customer segment.
- Sums those into a single risk score and classifies the order as **LOW**,
  **MEDIUM**, **HIGH**, or **CRITICAL**.
- LOW saves silently. MEDIUM and HIGH show an on-screen warning, and HIGH
  also fires an e-mail to the sales manager so it doesn't just scroll past
  unnoticed. CRITICAL blocks the save outright and escalates to senior
  management.
- Every evaluation — not just the risky ones — plus every manual
  approve/reject decision gets written to an audit log, `INSERT`-only, so
  there's always a real record of what the engine found and what a human
  did about it.
- A dashboard report lets you review flagged orders, drill into the
  per-check score behind any result, approve or reject an order straight
  from the grid, and export the list to Excel.
- Scoring weights and thresholds live in a config table, not in the code —
  tightening a threshold or switching a check off entirely is a table
  change, not a transport.

## Technical architecture

8 classes plus 1 executable report, split across `src/core` (domain logic:
entity, config, checker, notifier, logger), `src/badi` (orchestration and
the BAdI entry point), and `src/report` (the dashboard). The engine that
scores, logs, and notifies never raises an exception and never blocks
anything — it's the BAdI implementation, and only the BAdI implementation,
that turns a CRITICAL result into an actual `MESSAGE TYPE 'E'`. That split
is what lets the same engine be called safely from a batch job, a report,
or a unit test, not just from VA01. Scoring is entirely config-driven, and
every mock data block carries the real SQL as a comment above it, ready to
be swapped in.

Full write-up: [docs/architecture.md](docs/architecture.md)

## Project structure

```
03-order-risk-engine/
├── src/
│   ├── core/
│   │   ├── ZCL_ORDER_RISK_ENTITY.abap      # shared types & constants
│   │   ├── ZCL_ORDER_RISK_CONFIG.abap      # scoring config (weights/thresholds)
│   │   ├── ZCL_ORDER_RISK_CHECKER.abap     # the 7 risk checks + scoring
│   │   ├── ZCL_ORDER_RISK_NOTIFIER.abap    # HIGH/CRITICAL e-mail alerts
│   │   └── ZCL_ORDER_RISK_LOGGER.abap      # audit log, INSERT-only
│   ├── badi/
│   │   ├── ZCL_ORDER_RISK_ENGINE.abap      # orchestrates checker → logger → notifier
│   │   └── ZCL_IM_ORDER_RISK.abap          # BAdI entry point, owns the block decision
│   └── report/
│       ├── ZCL_ORDER_RISK_ALV.abap         # dashboard: grouped ALV, approve/reject/details/export
│       └── ZORDER_RISK_MONITOR.abap        # executable report, selection screen, screen 100
├── docs/
│   ├── architecture.md
│   ├── business-scenario.md
│   └── badi-setup-guide.md
└── README.md
```

## How to run / deploy

The complete, click-by-click walkthrough — creating the three Z-tables,
activating all 8 classes in the right order, finding and wiring the BAdI
(SE18/SE19), building the report, screen 100, GUI status and title, filling
the config table, and testing in VA01 — is in
[docs/badi-setup-guide.md](docs/badi-setup-guide.md). It's written for
someone who's never touched a BAdI before, so it explains the "why" at
every step, not just the clicks.

Short version, if you already know your way around SE11/SE24/SE18/SE19:

1. Create the three Z-tables in SE11: `ZORDER_RISK_LOG`, `ZORDER_BLACKLIST`,
   `ZORDER_RISK_CONFIG`.
2. Activate the 8 classes in SE24, **in dependency order** — this is the
   part most likely to trip you up if skipped:
   `entity → config → checker → notifier → logger → engine → alv → im`
   (i.e. `ZCL_ORDER_RISK_ENTITY` first, `ZCL_IM_ORDER_RISK` last).
3. Find the sales-order-save BAdI on your system (`BADI_SD_SALES_ITEM`,
   `BADI_SALES_ORDER_SAVE`, or the classic `SD_SALES_DOCUMENT_SAVE` — they
   vary by release) and wire it to `ZCL_IM_ORDER_RISK->on_order_save`
   through a thin adapter implementation, as described in the class header
   of `ZCL_IM_ORDER_RISK` and in the setup guide.
4. Create the report `ZORDER_RISK_MONITOR`, screen 100 (custom control
   `ALV_CONTAINER`), GUI status `STATUS100`, and title `TITLE100`.
5. Fill `ZORDER_RISK_CONFIG` with the seven checks' weights and thresholds.
6. Test in VA01 by saving orders against the mock customers set up to
   produce LOW, HIGH, and CRITICAL results, then check the dashboard.

## Roadmap

- Real Open SQL access in place of every mock data block (the SQL is
  already sketched in a comment above each one).
- ABAP Unit tests for each of the seven checks and for the score-to-level
  mapping.
- An SM30 maintenance view over `ZORDER_RISK_CONFIG`, so risk owners can
  retune weights and thresholds without a developer in the loop.
- Additional checks — dunning level, delivery block history — slotting in
  the same way the existing seven do.
- Workflow integration for HIGH approvals, instead of relying on someone
  reading an e-mail.

---

# Order Risk Engine

Gerçek bir SAP ABAP uygulamasını taklit eden bir portfolyo çalışması: bir
satış siparişi tam kaydedildiği anda devreye giren, siparişi 7 ağırlıklı
kontrolden geçiren, en tehlikeli siparişleri doğrudan bloklayan, geri
kalanı için yönetime e-posta atan ve her değerlendirmeyi audit log'a yazan,
BAdI tabanlı bir risk motoru. Nesne Yönelimli ABAP (OO ABAP) ile yazıldı.

> Burada gerçek veritabanı erişimi yerine mock veri kullanılıyor (kredi ve
> ödeme için `KNKK`/`BSID`, sipariş ve fiyatlama için
> `VBAK`/`VBAP`/`KONV`, stok için `MARD`, ayrıca bu projenin tanımladığı üç
> Z-tablo). Her mock bloğunun hemen üstünde gerçek `SELECT`/`INSERT`
> yorum satırı olarak duruyor, yani ileride gerçek tablolara geçmek mock'u
> silip SQL'in yorumunu kaldırmaktan ibaret. Detaylı anlatım
> [docs/architecture.md](docs/architecture.md) dosyasında.

## İş senaryosu

Siparişlerin büyük çoğunluğu sorunsuz, ama bazıları gerçek bir risk
taşıyor — kredi limitini aşmış bir müşteri, kronik geç ödeyen biri, o
müşterinin bugüne kadar verdiğinden çok daha büyük bir sipariş, aslında
depoda olmayan bir stok, kara listeye alınması gereken bir müşteri/malzeme
çifti, politikanın izin verdiğinin çok ötesinde bir iskonto. Bunların
hiçbiri standart sipariş akışında sert bir dur işareti olarak çıkmıyor, ve
biri fark ettiğinde sipariş genelde çoktan sevk edilmiş oluyor. Bu motor,
her siparişi kaydedildiği anda otomatik olarak puanlayarak bu boşluğu
kapatıyor — farklı ekiplerin elinde dağınık duran risk sinyallerine
güvenmek yerine.

Tam yazı: [docs/business-scenario.md](docs/business-scenario.md)

## Ne yapar

- Bir satış siparişi kaydedildiği anda, bir BAdI üzerinden bağlanarak
  otomatik çalışır — kimsenin bir kontrolü hatırlayıp tetiklemesi
  gerekmez.
- Siparişi 7 ağırlıklı risk kontrolünden geçirir: kredi limiti, ödeme
  performansı, sipariş anomalisi, stok, kara liste, fiyat sapması ve
  müşteri segmenti.
- Bunları tek bir risk skorunda toplar ve siparişi **LOW**, **MEDIUM**,
  **HIGH** ya da **CRITICAL** olarak sınıflandırır.
- LOW sessizce kaydedilir. MEDIUM ve HIGH ekranda bir uyarı gösterir, HIGH
  ayrıca satış müdürüne bir e-posta gönderir ki durum fark edilmeden
  geçmesin. CRITICAL kaydı doğrudan engeller ve üst yönetime yükseltir.
- Sadece riskli olanlar değil, yapılan her değerlendirme — ve her manuel
  onay/red kararı — audit log'a yazılır, sadece `INSERT` ile, yani
  motorun bulduğu şey ile bir insanın buna karşı ne yaptığı her zaman
  ayrı ayrı kayıt altında kalır.
- Bir dashboard raporu, işaretlenmiş siparişleri gözden geçirmene,
  herhangi bir sonucun arkasındaki kontrol bazlı detaya inmene, bir
  siparişi doğrudan grid üzerinden onaylayıp reddetmene ve listeyi
  Excel'e aktarmana imkân verir.
- Puanlama ağırlıkları ve eşikler kodda değil bir config tablosunda
  duruyor — bir eşiği sıkılaştırmak ya da bir kontrolü tamamen kapatmak
  bir tablo değişikliği, transport gerektiren bir kod değişikliği değil.

## Teknik mimari

8 sınıf artı 1 çalıştırılabilir rapor; `src/core` (domain mantığı: entity,
config, checker, notifier, logger), `src/badi` (orkestrasyon ve BAdI giriş
noktası) ve `src/report` (dashboard) olarak ayrılmış durumda. Puanlayan,
log'layan ve bildirim gönderen engine hiçbir zaman exception fırlatmıyor,
hiçbir şeyi bloklamıyor — bir CRITICAL sonucu gerçek bir `MESSAGE TYPE
'E'`'ye çeviren tek yer, ve sadece o yer, BAdI implementasyonu. Bu ayrım,
aynı engine'in VA01 dışında bir batch job'dan, bir rapordan ya da bir unit
test'ten de güvenle çağrılabilmesini sağlıyor. Puanlama tamamen config
güdümlü, ve her mock veri bloğunun üstünde, yerine geçecek gerçek SQL zaten
yorum satırı olarak yazılı.

Tam yazı: [docs/architecture.md](docs/architecture.md)

## Proje yapısı

```
03-order-risk-engine/
├── src/
│   ├── core/
│   │   ├── ZCL_ORDER_RISK_ENTITY.abap      # ortak tipler ve sabitler
│   │   ├── ZCL_ORDER_RISK_CONFIG.abap      # puanlama config'i (ağırlık/eşik)
│   │   ├── ZCL_ORDER_RISK_CHECKER.abap     # 7 risk kontrolü + puanlama
│   │   ├── ZCL_ORDER_RISK_NOTIFIER.abap    # HIGH/CRITICAL e-posta uyarıları
│   │   └── ZCL_ORDER_RISK_LOGGER.abap      # audit log, sadece INSERT
│   ├── badi/
│   │   ├── ZCL_ORDER_RISK_ENGINE.abap      # checker → logger → notifier'ı yönetir
│   │   └── ZCL_IM_ORDER_RISK.abap          # BAdI giriş noktası, bloklama kararını verir
│   └── report/
│       ├── ZCL_ORDER_RISK_ALV.abap         # dashboard: gruplu ALV, onay/red/detay/export
│       └── ZORDER_RISK_MONITOR.abap        # çalıştırılabilir rapor, seçim ekranı, screen 100
├── docs/
│   ├── architecture.md
│   ├── business-scenario.md
│   └── badi-setup-guide.md
└── README.md
```

## Nasıl çalıştırılır / kurulur

Üç Z-tablosunun oluşturulmasından 8 sınıfın doğru sırayla aktive
edilmesine, BAdI'nin bulunup bağlanmasına (SE18/SE19), rapor, screen 100,
GUI status ve title oluşturulmasına, config tablosunun doldurulmasına ve
VA01'de test edilmesine kadar tüm adımları içeren eksiksiz rehber
[docs/badi-setup-guide.md](docs/badi-setup-guide.md) içinde. Daha önce hiç
BAdI'ye dokunmamış biri için yazıldı, yani her adımda sadece ne
tıklanacağını değil, nedenini de anlatıyor.

SE11/SE24/SE18/SE19'a zaten aşinaysan, kısa versiyon şu:

1. SE11'de üç Z-tablosunu oluştur: `ZORDER_RISK_LOG`, `ZORDER_BLACKLIST`,
   `ZORDER_RISK_CONFIG`.
2. 8 sınıfı SE24'te **bağımlılık sırasına göre** aktive et — atlanırsa en
   çok burada takılırsın:
   `entity → config → checker → notifier → logger → engine → alv → im`
   (yani önce `ZCL_ORDER_RISK_ENTITY`, en son `ZCL_IM_ORDER_RISK`).
3. Sisteminde satış siparişi kaydetme BAdI'sini bul (`BADI_SD_SALES_ITEM`,
   `BADI_SALES_ORDER_SAVE`, ya da klasik `SD_SALES_DOCUMENT_SAVE` —
   sürüme göre değişir) ve `ZCL_IM_ORDER_RISK`'in class header'ında ve
   setup rehberinde anlatıldığı gibi ince bir adaptör implementasyonu
   üzerinden `on_order_save`'e bağla.
4. `ZORDER_RISK_MONITOR` raporunu, screen 100'ü (custom control
   `ALV_CONTAINER`), `STATUS100` GUI status'ünü ve `TITLE100` başlığını
   oluştur.
5. `ZORDER_RISK_CONFIG`'i yedi kontrolün ağırlıkları ve eşik değerleriyle
   doldur.
6. VA01'de LOW, HIGH ve CRITICAL sonuç üretecek şekilde ayarlanmış mock
   müşterilere karşı sipariş kaydederek test et, sonra dashboard'u kontrol
   et.

## Yol haritası

- Her mock veri bloğunun yerine, üstünde zaten taslağı yazılı gerçek Open
  SQL erişimi.
- Yedi kontrolün her biri ve skor-seviye eşlemesi için ABAP Unit testleri.
- `ZORDER_RISK_CONFIG` üzerine bir SM30 bakım görünümü, risk sahiplerinin
  bir geliştirici olmadan ağırlık ve eşikleri ayarlayabilmesi için.
- Mevcut yedi kontrolün eklendiği şekilde eklenebilecek yeni kontroller —
  ihtar (dunning) seviyesi, teslimat blok geçmişi.
- HIGH onayları için, birinin e-posta kutusunu okumasına güvenmek yerine
  workflow entegrasyonu.