# Order Risk Engine — BAdI Kurulum Rehberi / BAdI Setup Guide

> Bu rehber iki dilde yazılmıştır: önce **Türkçe**, ardından `---` ayracının altında **İngilizce**. İçerik her iki dilde birebir aynı adımları içerir.
>
> This guide is written in two languages: **Turkish** first, then **English** below the `---` separator. Both versions cover exactly the same steps.

---

# TÜRKÇE

## 1. Genel Bakış

Order Risk Engine, bir satış siparişi kaydedilmeden önce çalışan, siparişi 7 farklı açıdan (kredi limiti, ödeme performansı, sipariş anomalisi, stok, kara liste, fiyat sapması, müşteri segmenti) puanlayan ve puana göre siparişi bilgilendirici bir uyarıyla geçiren ya da tamamen engelleyen bir risk motorudur. Sonuçlar bir log tablosuna yazılır, yüksek riskli siparişlerde e-posta gönderilir ve bir ALV dashboard raporu üzerinden izlenebilir.

Kurulumu **belirli bir sırayla** yapmamızın nedeni basit: ABAP'ta bir sınıf, henüz var olmayan başka bir sınıfa referans veriyorsa aktive edilemez (syntax hatası verir). Bu yüzden önce hiçbir şeye bağımlı olmayan temel nesneleri (tablolar, ENTITY sınıfı), sonra onlara bağımlı olanları, en son da her şeyi bir araya getiren rapor ve BAdI'yi oluşturacağız.

### Oluşturulacak nesnelerin tam listesi

| # | Tip | Nesne adı | Nerede oluşturulur |
|---|-----|-----------|---------------------|
| 1 | Z-Tablo | ZORDER_RISK_LOG | SE11 |
| 2 | Z-Tablo | ZORDER_BLACKLIST | SE11 |
| 3 | Z-Tablo | ZORDER_RISK_CONFIG | SE11 |
| 4 | Sınıf | ZCL_ORDER_RISK_ENTITY | SE24 |
| 5 | Sınıf | ZCL_ORDER_RISK_CONFIG | SE24 |
| 6 | Sınıf | ZCL_ORDER_RISK_CHECKER | SE24 |
| 7 | Sınıf | ZCL_ORDER_RISK_NOTIFIER | SE24 |
| 8 | Sınıf | ZCL_ORDER_RISK_LOGGER | SE24 |
| 9 | Sınıf | ZCL_ORDER_RISK_ENGINE | SE24 |
| 10 | Sınıf | ZCL_ORDER_RISK_ALV | SE24 |
| 11 | Sınıf | ZCL_IM_ORDER_RISK (adaptör hedefi) | SE24 |
| 12 | BAdI Implementasyonu | (bulduğunuz BAdI'ye göre, örn. ZIM_ORDER_RISK) | SE19 |
| 13 | Program (Rapor) | ZORDER_RISK_MONITOR | SE38 |
| 14 | Ekran | Screen 100 (Custom Control: ALV_CONTAINER) | SE51 |
| 15 | GUI Status | STATUS100 | SE41 (veya SE38 içinden) |
| 16 | Başlık (Title) | TITLE100 | SE41 (veya SE38 içinden) |

Toplamda: **3 Z-tablo, 8 sınıf (core/badi/report klasörlerine dağılmış), 1 BAdI implementasyonu, 1 rapor, 1 ekran, 1 GUI status, 1 title.**

---

## 2. Z-Tablolarının Oluşturulması (SE11)

### Genel kavramlar (ilerlemeden önce okuyun)

- **Delivery Class A**: Bu, tablonun "uygulama tablosu" (Application table) olduğunu, yani müşteri verisi tuttuğunu belirtir. SAP'nin kendi tabloları genellikle Delivery Class S/C/G/E gibi farklı sınıflardadır. Kendi Z-tablolarımız için her zaman **A** seçilir; aksi halde tablo içeriği bir sistem kopyalama/upgrade işleminde yanlış davranabilir.
- **MANDT neden her zaman ilk key alanı?**: SAP çok client'lı (multi-client) bir sistemdir — aynı sunucuda birden fazla client (100, 200, 300 gibi) bulunur ve her client'ın verisi birbirinden izole olmalıdır. MANDT (client) alanı olmadan bir client'taki veri, yanlışlıkla başka bir client'ta görünebilir. Bu yüzden client-bağımlı her Z-tabloda MANDT, **ilk** key alanı olarak eklenir.
- **"Aktive etmek" (Activate) ne yapar?**: Tabloyu SE11'de tanımladığınızda önce sadece bir "taslak" (inactive version) olarak kaydedilir. Aktive etme işlemi (Ctrl+F3), bu taslağı gerçek veritabanı nesnesine (fiziksel tabloya) dönüştürür. Aktive edilmemiş bir tablo ABAP kodunda kullanılamaz ve SELECT/INSERT yapılamaz.

### 2.1 Tablo: ZORDER_RISK_LOG

Bu tablo, her risk değerlendirmesinin ve her onay/red işleminin kalıcı kaydını tutar (audit log).

| Alan Adı | Key? | Data Element / Tip | Uzunluk | Açıklama |
|---|---|---|---|---|
| MANDT | ✔ | MANDT | 3 | Client |
| LOG_ID | ✔ | SYSUUID_C | 32 | Her log satırı için benzersiz kimlik (UUID) |
| VBELN | | VBELN | 10 | Satış siparişi numarası |
| KUNNR | | KUNNR | 10 | Müşteri numarası |
| CHECK_NAME | | CHAR30 | 30 | Hangi kontrolün sonucu (örn. CREDIT_LIMIT) |
| SCORE | | INT4 | 10 | Bu kontrolden alınan puan |
| RISK_LEVEL | | CHAR10 | 10 | LOW / MEDIUM / HIGH / CRITICAL |
| MESSAGE | | CHAR100 | 100 | Kontrolün açıklayıcı mesajı |
| ACTION | | CHAR20 | 20 | RISK_EVALUATED / APPROVED / REJECTED |
| UNAME | | SYUNAME | 12 | İşlemi yapan kullanıcı |
| DATUM | | SYDATUM | 8 | Tarih |
| UZEIT | | SYUZEIT | 6 | Saat |

**Adım adım SE11 talimatları:**

1. Komut kutusuna (ekranın sol üst köşesindeki beyaz kutu) `SE11` yazıp Enter'a basın. Karşınıza "ABAP Dictionary: Initial Screen" ekranı gelir.
2. "Database table" radio butonunun seçili olduğundan emin olun, isim kutusuna `ZORDER_RISK_LOG` yazın ve **Create** butonuna tıklayın.
3. Açılan pencerede bir "Short Description" (kısa açıklama) istenecek — örneğin `Order Risk Evaluation Log` yazıp Enter'a basın.
4. **Delivery and Maintenance** sekmesinde **Delivery Class** alanına `A` yazın (Application table, master and transaction data). Bu adım önemlidir; boş bırakırsanız aktivasyon sırasında uyarı alırsınız.
5. **Fields** sekmesine geçin. İlk satıra `MANDT` yazın, Key kutucuğunu işaretleyin, Data Element olarak `MANDT` girin (Enter'a bastığınızda uzunluk ve açıklama otomatik dolar).
6. Sonraki satıra `LOG_ID` yazın, Key kutucuğunu işaretleyin, Data Element `SYSUUID_C` girin.
7. Kalan alanları yukarıdaki tablodaki sırayla, Key kutucuğunu **işaretlemeden**, girin (VBELN, KUNNR, CHECK_NAME, SCORE, RISK_LEVEL, MESSAGE, ACTION, UNAME, DATUM, UZEIT). Her satırda Data Element'i yazıp Enter'a bastığınızda tip ve uzunluk otomatik gelir; CHECK_NAME, RISK_LEVEL, MESSAGE, ACTION gibi hazır bir data element'iniz yoksa doğrudan Data Type sütununa `CHAR` yazıp Length sütununa uzunluğu (30, 10, 100, 20) girebilirsiniz.
8. Kaydedin (Ctrl+S). Bir "Package" (paket) sorulursa, portföy projesi için `$TMP` (local object, transport gerektirmez) kullanabilirsiniz; gerçek bir geliştirme sisteminde takım liderinizin belirttiği Z paketini kullanın.
9. Aktive edin: **Ctrl+F3** tuşuna basın veya araç çubuğundaki "Activate" (sarı-kırmızı simge) butonuna tıklayın. Alt kısımda "Object activated" mesajını görmelisiniz.

**Sık yapılan hata:** MANDT alanını unutmak veya key olarak işaretlememek. Bu durumda aktivasyon sırasında "Table has no key fields" gibi bir hata alırsınız — çözüm: Fields sekmesine dönüp MANDT'ı ekleyip Key kutucuğunu işaretlemek.

### 2.2 Tablo: ZORDER_BLACKLIST

Bu tablo, sipariş verilmesi yasak/riskli olan müşteri-malzeme kombinasyonlarını tutar.

| Alan Adı | Key? | Data Element / Tip | Uzunluk | Açıklama |
|---|---|---|---|---|
| MANDT | ✔ | MANDT | 3 | Client |
| KUNNR | ✔ | KUNNR | 10 | Müşteri numarası (boş = tüm müşteriler) |
| MATNR | ✔ | MATNR | 18 (ECC) / 40 (S/4HANA) | Malzeme numarası (boş = tüm malzemeler) |
| REASON | | CHAR100 | 100 | Kara listeye alınma nedeni |
| ACTIVE | | CHAR1 (abap_bool) | 1 | 'X' = aktif, boş = pasif |

**Adım adım:**

1. `SE11` → isim kutusuna `ZORDER_BLACKLIST` yazın → **Create**.
2. Kısa açıklama: `Order Blacklist (Customer/Material)`.
3. Delivery Class = `A`.
4. Fields sekmesinde MANDT, KUNNR, MATNR alanlarının hepsini **Key** olarak işaretleyin (üçü birlikte bileşik anahtarı oluşturur — bir satırın "bu müşteri + bu malzeme" kombinasyonunu tek şekilde tanımlaması gerekir).
5. ACTIVE alanını key OLMADAN ekleyin, Data Type `CHAR`, Length `1`.
6. Kaydedip aktive edin (Ctrl+S, sonra Ctrl+F3).

**Not:** KUNNR veya MATNR boş bırakılabilir (örneğin sadece müşteriye göre veya sadece malzemeye göre kısıtlama koymak için). Bu, ZCL_ORDER_RISK_CHECKER sınıfındaki `check_blacklist` metodunun tasarımıyla uyumludur.

### 2.3 Tablo: ZORDER_RISK_CONFIG

Bu tablo, her kontrolün maksimum puanını ve eşik değerlerini tutar — kodu değiştirmeden risk davranışını ayarlamamızı sağlayan tablo budur.

| Alan Adı | Key? | Data Element / Tip | Uzunluk | Açıklama |
|---|---|---|---|---|
| MANDT | ✔ | MANDT | 3 | Client |
| CHECK_NAME | ✔ | CHAR30 | 30 | Kontrol adı (örn. CREDIT_LIMIT) |
| MAX_SCORE | | INT4 | 10 | Bu kontrolün alabileceği maksimum puan |
| THRESHOLD_LOW | | INT4 | 10 | Düşük risk eşiği |
| THRESHOLD_HIGH | | INT4 | 10 | Yüksek risk eşiği |
| ACTIVE | | CHAR1 (abap_bool) | 1 | 'X' = bu kontrol çalışır, boş = atlanır |

**Adım adım:**

1. `SE11` → `ZORDER_RISK_CONFIG` → **Create**.
2. Kısa açıklama: `Order Risk Check Configuration`.
3. Delivery Class = `A`.
4. MANDT ve CHECK_NAME'i **Key** olarak işaretleyin. MAX_SCORE, THRESHOLD_LOW, THRESHOLD_HIGH, ACTIVE alanlarını key olmadan ekleyin.
5. Kaydedip aktive edin.

Üç tablo da tamamlandığında, **Tables** klasöründe (SE11 → Utilities → Where-Used, ya da SE80'de paket ağacında) üç tablonun da "Active" durumda göründüğünü kontrol edin.

---

## 3. ABAP Sınıflarının Oluşturulması (SE24)

### Neden bu sıra?

Aşağıdaki sıra, bağımlılık zincirini takip eder: her sınıf, listede kendisinden önce gelen sınıflara referans verir. Örneğin `ZCL_ORDER_RISK_CHECKER`, `ZCL_ORDER_RISK_CONFIG` ve `ZCL_ORDER_RISK_ENTITY` tiplerini kullanır; bu ikisi önce aktif olmazsa CHECKER derlenemez.

1. **ZCL_ORDER_RISK_ENTITY** — hiçbir şeye bağımlı değil; tüm ortak TYPES ve CONSTANTS burada tanımlı (dosya: `src/core/ZCL_ORDER_RISK_ENTITY.abap`)
2. **ZCL_ORDER_RISK_CONFIG** — ENTITY'deki tiplere bağımlı (dosya: `src/core/ZCL_ORDER_RISK_CONFIG.abap`)
3. **ZCL_ORDER_RISK_CHECKER** — ENTITY ve CONFIG'e bağımlı (dosya: `src/core/ZCL_ORDER_RISK_CHECKER.abap`)
4. **ZCL_ORDER_RISK_NOTIFIER** — ENTITY'ye bağımlı (dosya: `src/core/ZCL_ORDER_RISK_NOTIFIER.abap`)
5. **ZCL_ORDER_RISK_LOGGER** — ENTITY'ye bağımlı (dosya: `src/core/ZCL_ORDER_RISK_LOGGER.abap`)
6. **ZCL_ORDER_RISK_ENGINE** — CHECKER, NOTIFIER ve LOGGER'ı çağırıyor, üçü de önce aktif olmalı (dosya: `src/badi/ZCL_ORDER_RISK_ENGINE.abap`)
7. **ZCL_ORDER_RISK_ALV** — ENTITY ve LOGGER'a bağımlı, dashboard'u çizer (dosya: `src/report/ZCL_ORDER_RISK_ALV.abap`)
8. **ZCL_IM_ORDER_RISK** — ENGINE'i çağırıyor, en son aktive edilmeli (dosya: `src/badi/ZCL_IM_ORDER_RISK.abap`)

### Her sınıf için tekrar eden adımlar

Her bir sınıf için aşağıdaki adımları uygulayın:

1. Komut kutusuna `SE24` yazıp Enter'a basın.
2. "Object type" olarak **Class** seçili olduğundan emin olun, "Object name" kutusuna sınıfın tam adını (örn. `ZCL_ORDER_RISK_ENTITY`) yazın.
3. **Create** butonuna tıklayın. Açılan pencerede "Class Type" olarak `Class` seçin (varsayılan zaten budur), kısa açıklama girin (örn. `Order Risk - Common Types and Constants`) ve Enter'a basın.
4. Bu noktada SAP sizi görsel Class Builder ekranına götürür (metotları tek tek elle eklemenizi ister). Bunun yerine, dosyadaki hazır kodu doğrudan yapıştıracağız: üstteki menüden **Utilities → Convert to Source Code Editor** (bazı sürümlerde **Utilities → Source Code-Based Editing**) yolunu izleyin. Bu, ekranı tek bir düz metin editörüne çevirir; artık `CLASS ... DEFINITION` ve `CLASS ... IMPLEMENTATION` bloklarının ikisini birden aynı ekranda görürsünüz.
5. Editördeki mevcut şablonu tamamen silin (Ctrl+A, Delete) ve ilgili dosyanın **tüm içeriğini** (`src/core/...` veya `src/badi/...` veya `src/report/...` klasöründen) kopyalayıp yapıştırın.
6. Kaydedin (Ctrl+S). Paket sorulursa `$TMP` veya projenizin paketini seçin.
7. Aktive edin: **Ctrl+F3**. Alt kısımda hata yoksa "Object activated" mesajını görürsünüz. Hata varsa (örneğin "Type ZCL_ORDER_RISK_CONFIG is unknown"), bağımlı olduğu sınıfın henüz aktive edilmediğinden şüphelenin — sıradaki adımı kontrol edin.

**Önemli not:** Her dosyayı kendi klasöründen alın — `core/` klasöründeki 5 sınıf (ENTITY, CONFIG, CHECKER, NOTIFIER, LOGGER), `badi/` klasöründeki 2 sınıf (ENGINE, ZCL_IM_ORDER_RISK), `report/` klasöründeki 1 sınıf (ALV). Yanlış dosyayı yanlış sınıfa yapıştırmak derleme hatası verir.

**Sık yapılan hata:** Sınıfları rastgele sırayla aktive etmeye çalışmak. ABAP, henüz tanımlanmamış bir tipe (örneğin bağımlı sınıf henüz oluşturulmadıysa) referans veren kodu aktive etmeyi reddeder. Hata mesajında geçen sınıf adını bulup önce onu oluşturduğunuzdan emin olun.

---

## 4. BAdI'nin Bulunması ve Implemente Edilmesi (SE18 / SE19)

Bu, rehberin **en kritik ve en detaylı** bölümüdür — lütfen aceleye getirmeyin.

### BAdI nedir? (basit anlatım)

BAdI (Business Add-In), SAP'nin standart programının içine, SAP'nin kendi kodunu değiştirmeden (modification yapmadan) kendi kodunuzu "iğneleyebileceğiniz" resmi bir bağlantı noktasıdır (hook). SAP, belirli bir işlem anında (örneğin bir satış siparişi kaydedilirken) sizin yazdığınız sınıfın belirli bir metodunu otomatik olarak çağırır. Böylece SAP'nin orijinal programını (ör. sipariş kaydetme mantığını) bozmadan, kendi risk kontrolümüzü araya sokabiliriz. Bu, upgrade güvenliği sağlar: SAP'nin kodu değişse bile sizin BAdI implementasyonunuz genelde çalışmaya devam eder.

### Adım 1 — BAdI tanımını (definition) aramak için SE18

Komut kutusuna `SE18` yazıp Enter'a basın. **SE18, BAdI tanımlarını ARAMAK/GÖRÜNTÜLEMEK** için kullanılır — burada implementasyon (kendi kodunuz) OLUŞTURMAZSINIZ, sadece "böyle bir BAdI var mı, varsa hangi metotları var" diye bakarsınız.

### Adım 2 — Satış siparişi kaydetme BAdI'sini aramak

SAP sürümüne göre bu BAdI'nin adı değişir; bu yüzden aşağıdaki adayları **sırayla** deneyin:

1. `BADI_SD_SALES_ITEM` — S/4HANA'da kalem (item) seviyesinde çalışan güncel BAdI.
2. `BADI_SALES_ORDER_SAVE` — daha yeni S/4HANA sürümlerindeki kaydetme BAdI'si.
3. `SD_SALES_DOCUMENT_SAVE` — klasik ECC BAdI'si.

Her birini SE18 ekranındaki isim kutusuna yazıp **Display** (gözlük simgesi) butonuna tıklayarak deneyin. Eğer BAdI mevcutsa, tanımın detay ekranı (Interface, metotlar, filtreler) açılır. Eğer mevcut değilse, "Enhancement spot &1 does not exist" veya benzeri bir hata mesajı alırsınız — bu durumda listedeki bir sonraki adayı deneyin.

**Var olduğunu nasıl anlarsınız?** Display ekranı hatasız açılıyorsa ve sol tarafta "Interfaces" altında en az bir metot (örn. `SAVE_DOCUMENT_PREPARE` gibi) görüyorsanız, bu BAdI sisteminizde mevcut demektir.

### Adım 3 — Hiçbiri yoksa: klasik user exit (MV45AFZZ)

Bazı eski ECC sistemlerinde yukarıdaki BAdI'lerin hiçbiri bulunmayabilir. Bu durumda klasik "user exit" mekanizmasına geri dönülür:

- `SMOD` işlem koduyla `VA00001` (satış siparişi user exit'lerinin bulunduğu enhancement) aranır.
- `CMOD` işlem koduyla bir "proje" oluşturulup bu enhancement'a atanır ve aktive edilir.
- Gerçek kodunuz, `MV45AFZZ` include'ı içindeki `USEREXIT_SAVE_DOCUMENT_PREPARE` form rutininde yazılır.

Bu yöntem daha eskidir ve BAdI kadar esnek değildir (aynı include'da birden fazla ekip çalışırsa çakışma riski vardır), ama hâlâ birçok ECC sisteminde tek seçenektir. Bu rehberin kapsamı dışında olduğu için burada sadece yol gösteriyoruz; mantık aynı: adaptör kodunu (Adım 5) bu form rutininin içine yazarsınız.

### Adım 4 — SE19 ile implementasyon OLUŞTURMAK

Komut kutusuna `SE19` yazın. Bu sefer **implementasyon oluşturuyoruz** (kendi kodumuzu bağlıyoruz).

1. "New Implementation" (veya "Create") seçeneğini işaretleyin.
2. "Enhancement Spot" veya "BAdI Definition" kutusuna, Adım 2'de bulduğunuz BAdI adını girin (örn. `BADI_SD_SALES_ITEM`) ve Enter'a basın.
3. "Implementation" adı kutusuna kendi implementasyon adınızı girin, örneğin `ZIM_ORDER_RISK`, ve Enter'a basın.
4. SAP size otomatik olarak bir "Implementing Class" adı önerecektir (genelde implementasyon adına benzer bir isim, örn. `ZCL_IM_ORDER_RISK`).
   **⚠️ ÇOK ÖNEMLİ:** Bu önerilen ismi **kabul etmeyin** — projede zaten `ZCL_IM_ORDER_RISK` adında, SE24'te Bölüm 3'te oluşturduğunuz bambaşka bir sınıf var (adaptör hedefi). İsim çakışması olursa aktivasyon hata verir veya yanlış sınıfın üzerine yazarsınız. Bunun yerine implementing class alanına açıkça farklı bir isim yazın, örneğin `ZCL_BADI_ORDER_RISK_IMPL`.
5. Enter'a basıp devam edin; SAP implementasyon ve implementing class'ı (boş bir iskeletle) oluşturur.
6. Kaydedin (paket `$TMP` veya proje paketiniz).

### Adım 5 — Adaptör kodunu yapıştırmak

Az önce oluşturulan `ZCL_BADI_ORDER_RISK_IMPL` sınıfının (SE19 ekranında "Interface" veya "Methods" sekmesi altında görünen) ilgili metoduna çift tıklayın — bu sizi kod editörüne götürür. Buraya, `ZCL_IM_ORDER_RISK.abap` dosyasının başındaki yorum bloğunda örneklenen adaptör kodunu (BAdI'nizin gerçek parametre adlarına göre uyarlayarak) yazın:

```abap
METHOD if_ex_badi_sd_sales_item~save_document_prepare.

  DATA(lo_risk) = NEW zcl_im_order_risk( ).

  DATA(lt_items) = VALUE zcl_order_risk_entity=>ty_order_items(
    FOR ls_vbap IN it_vbap
    ( matnr = ls_vbap-matnr
      menge = ls_vbap-kwmeng
      netpr = ls_vbap-netpr
      kpein = ls_vbap-kpein
      werks = ls_vbap-werks ) ).

  lo_risk->on_order_save(
    iv_vbeln = is_vbak-vbeln
    iv_kunnr = is_vbak-kunnr
    it_items = lt_items ).

ENDMETHOD.
```

Bu kodun görevi tek bir şey: SAP'nin size verdiği VBAK/VBAP verisini (veya BAdI'nizin IMPORTING/CHANGING parametrelerini) `ZCL_IM_ORDER_RISK`'in beklediği basit tiplere (`ty_order_items`) dönüştürüp `on_order_save()` metodunu çağırmak. Metot adı, parametre adları ve tablo adları kullandığınız gerçek BAdI'ye göre değişebilir — bu yüzden bu kodu olduğu gibi değil, bulduğunuz BAdI'nin gerçek arayüzüne göre uyarlayarak yapıştırın.

### Adım 6 — Aktive etmek

`Ctrl+F3` ile hem metodu hem de implementasyonun kendisini (SE19 ana ekranında da bir Activate butonu vardır) aktive edin. Aktivasyondan sonra implementasyon "Active" durumda görünmelidir — pasif kalan implementasyonlar SAP tarafından hiç çağrılmaz.

### Sık yapılan hatalar

- **Yanlış seviyede BAdI seçmek (item vs. header):** `BADI_SD_SALES_ITEM` kalem (item) seviyesinde çalışır ve genelde birden fazla kez (her kalem için) tetiklenir; `BADI_SALES_ORDER_SAVE` ise belge (header) seviyesinde bir kez çalışır. Yanlış seviyeyi seçerseniz `on_order_save()` ya birden fazla kez ya da eksik veriyle çağrılabilir. BAdI'nin dokümantasyonunu (SE18 ekranında "Documentation" butonu) mutlaka okuyun.
- **Metot imzası uyuşmazlığı:** Adaptör kodundaki `it_vbap`, `is_vbak` gibi parametre adları örnektir — gerçek BAdI'nizin IMPORTING/CHANGING parametre adları farklı olabilir. SE19'da metoda çift tıkladığınızda üstte gerçek parametre listesini görürsünüz; kodu ona göre uyarlayın.
- **Implementasyonu aktive etmeyi unutmak:** Kod hatasız derlense bile implementasyon "Inactive" durumda kalırsa BAdI hiç tetiklenmez. Sipariş kaydedip hiçbir mesaj görmüyorsanız ilk kontrol noktanız burası olmalı.

---

## 5. Raporun ve Ekranın Oluşturulması (SE38 / SE51)

### 5.1 SE38 ile programı oluşturmak

1. Komut kutusuna `SE38` yazın, program adı olarak `ZORDER_RISK_MONITOR` girin, **Create** butonuna tıklayın.
2. Açılan "Program Attributes" penceresinde: Title = `Order Risk Dashboard`, Type = `Executable Program`, Status = `Test Program` (isteğe bağlı) seçip kaydedin.
3. Kod editörü açıldığında, `src/report/ZORDER_RISK_MONITOR.abap` dosyasının tüm içeriğini yapıştırın.
4. Kaydedin (Ctrl+S) ama **henüz aktive etmeyin** — çünkü kod, henüz var olmayan Screen 100'e (`CALL SCREEN 100`) ve henüz var olmayan `STATUS100`/`TITLE100`'e referans veriyor. Önce ekranı ve status'ü oluşturmamız, sonra hepsini birlikte aktive etmemiz gerekiyor.

### 5.2 SE51 (Screen Painter) ile Screen 100'ü oluşturmak

1. Komut kutusuna `SE51` yazın. Program adı `ZORDER_RISK_MONITOR`, Screen number `100` girin, **Create** butonuna tıklayın.
2. Screen Attributes ekranında Short description = `Order Risk Dashboard Screen` girin, Screen Type = `Normal` bırakın, kaydedin.
3. **Layout** (Grafik editörü) butonuna tıklayın. Açılan boş ekran tuvalinde, sol taraftaki eleman paletinden **Custom Control** elemanını sürükleyip ekranın büyük bir bölümüne (ideal olarak ekranın tamamına yakın, üstte biraz boşluk bırakarak) yerleştirin.
4. Yerleştirdiğiniz custom control'e çift tıklayın, açılan özellikler penceresinde **Name** alanına tam olarak `ALV_CONTAINER` yazın. **Bu isim harfi harfine doğru olmalı** — çünkü `ZCL_ORDER_RISK_ALV` sınıfının `display()` metodu, `cl_gui_custom_container` nesnesini oluştururken `container_name = 'ALV_CONTAINER'` sabit değerini kullanıyor. İsimler eşleşmezse ALV ekranda hiç görünmez, boş bir ekran görürsünüz.
5. Layout editöründen çıkıp (Back) Screen Painter ana ekranına dönün.
6. **Flow Logic** sekmesine geçin. Burada PBO (Process Before Output) ve PAI (Process After Input) bloklarını göreceksiniz; SAP genelde `MODULE STATUS_0100.` gibi bir satırı otomatik önerir. İçeriği aşağıdaki gibi olacak şekilde düzenleyin:

```abap
PROCESS BEFORE OUTPUT.
  MODULE status_0100.
  MODULE display_alv_0100.

PROCESS AFTER INPUT.
  MODULE user_command_0100.
```

7. Kaydedin, ama henüz aktive etmeyin (GUI Status ve Title de eksik olduğu için aktivasyon uyarı/hata verecektir; hepsini birlikte tamamlayıp en son aktive edeceğiz).

### 5.3 GUI Status'ü oluşturmak (STATUS100)

1. `SE38`'de `ZORDER_RISK_MONITOR` programını açın (Change modunda), üst menüden **Goto → PF-Status...** yolunu izleyin (bazı sürümlerde bunun için doğrudan `SE41` işlem kodunu kullanıp program adı + status adı girmeniz istenir).
2. Status adı olarak `STATUS100` girin, Enter'a basın; "does not exist, create?" sorusuna Evet deyin.
3. Açılan Menu Painter ekranında, "Function Keys" veya "Standard Toolbar" bölümüne üç fonksiyon kodu ekleyin:
   - `BACK` (genelde F3 tuşuna atanır, ikonu geri ok)
   - `EXIT` (genelde Shift+F3)
   - `CANCEL` (genelde F12, ikonu kırmızı X)
4. Bu üç kodun tam olarak `BACK`, `EXIT`, `CANCEL` yazıldığından emin olun — çünkü `ZORDER_RISK_MONITOR` raporundaki `user_command_0100` modülü `sy-ucomm` değerini tam olarak bu üç metinle karşılaştırıyor.
5. Kaydedip aktive edin.

### 5.4 Title'ı oluşturmak (TITLE100)

1. Aynı program içinde **Goto → Titles...** (veya Text Elements → Titles) yolunu izleyin.
2. Title adı `TITLE100`, metin `Order Risk Dashboard` girin.
3. Kaydedin ve aktive edin.

### 5.5 Text Symbols'leri girmek

1. **Goto → Text Elements → Text Symbols** yolunu izleyin (veya SE38 program özelliklerinden Text Elements ikonuna tıklayın).
2. Aşağıdaki iki satırı girin:

   | Sym | Text |
   |-----|------|
   | 001 | Date Range |
   | 002 | Risk Filters |

3. Kaydedin ve aktive edin. Bu metinler, seçim ekranındaki `BLOCK b01`/`b02` çerçevelerinin başlıkları olarak görünecektir.

### 5.6 Her şeyi birlikte aktive etmek

Artık program, ekran, status ve title tamamlandığına göre `SE38`'e dönüp `ZORDER_RISK_MONITOR` programını **Ctrl+F3** ile aktive edin. "Inactive objects" listesi açılırsa (program + screen 100 + status + title hepsi listelenir), **hepsini seçip** birlikte aktive edin. Hata yoksa artık `SE38` → **Direct Processing** (F8) ile raporu çalıştırabilirsiniz.

---

## 6. Konfigürasyon Verilerinin Girilmesi

### 6.1 ZORDER_RISK_CONFIG tablosunu doldurmak

Komut kutusuna `SE16N` yazın (veya `SM30` ile — SM30, tablo bakım görünümü olmadığı için doğrudan tablo adıyla "generic table maintenance" uyarısı verebilir; bu portföy projesinde en basit yöntem SE16N'dir). `SE16N`'de tablo adına `ZORDER_RISK_CONFIG` yazıp Enter'a basın, sonra araç çubuğundaki **kalem/edit** ikonuna tıklayıp yeni satır ekleme moduna geçin (`SE16N`'de veri girişi için genelde sistem parametresi `&SAP_EDIT` gerekir; yoksa sisteminizde `SM30` ile bir bakım görünümü (maintenance view) tanımlanmış olmalı — bunun için ekibinizdeki bir Basis/ABAP danışmanına danışın).

Aşağıdaki 7 satırı, kodun içindeki (`ZCL_ORDER_RISK_CONFIG` sınıfının mock verisiyle birebir uyumlu) varsayılan değerlerle girin:

| CHECK_NAME | MAX_SCORE | THRESHOLD_LOW | THRESHOLD_HIGH | ACTIVE |
|---|---|---|---|---|
| CREDIT_LIMIT | 25 | 10 | 20 | X |
| PAYMENT_PERF | 20 | 8 | 15 | X |
| ORDER_ANOMALY | 15 | 6 | 12 | X |
| STOCK | 15 | 6 | 12 | X |
| BLACKLIST | 25 | 0 | 25 | X |
| PRICE_DEV | 10 | 4 | 8 | X |
| CUSTOMER_SEG | 10 | 4 | 8 | X |

Bu 7 satırın MAX_SCORE toplamı 120'dir. Toplam risk puanı şu eşiklere göre sınıflandırılır (bunlar `ZCL_ORDER_RISK_ENTITY` sınıfında sabit olarak tanımlıdır, config tablosunda değil): 31 ve üzeri = MEDIUM, 61 ve üzeri = HIGH, 86 ve üzeri = CRITICAL.

### 6.2 ZORDER_BLACKLIST tablosuna satır eklemek

Aynı şekilde `SE16N` (veya `SM30`) ile `ZORDER_BLACKLIST` tablosuna, örnek olarak şu iki satırı ekleyebilirsiniz:

| KUNNR | MATNR | REASON | ACTIVE |
|---|---|---|---|
| 0000100002 | (boş) | Customer under investigation | X |
| (boş) | MAT100030 | Restricted material | X |

İlk satır, "bu müşteri hangi malzemeyi sipariş ederse etsin engellenir" anlamına gelir (MATNR boş). İkinci satır ise "bu malzeme hangi müşteri tarafından sipariş edilirse edilsin engellenir" anlamına gelir (KUNNR boş).

### 6.3 Neden bu önemli?

Bu iki tablonun tüm amacı, **kod değiştirmeden** risk davranışını değiştirebilmektir. Örneğin bir kontrolü tamamen kapatmak isterseniz (`ACTIVE` = boş yaparsınız), bir eşiği sıkılaştırmak isterseniz (THRESHOLD_HIGH'ı düşürürsünüz), ya da yeni bir riskli müşteri eklemek isterseniz — hiçbirinde ABAP kodunu açıp değiştirmeniz gerekmez, sadece tabloya bir satır ekler/değiştirirsiniz. Bu, config-driven (konfigürasyon güdümlü) tasarımın tüm amacıdır.

---

## 7. Mock Veriden Gerçek Tablolara Geçiş

Şu anda proje, gerçek bir SAP sistemine ihtiyaç duymadan test edilebilmesi için **her kontrol ve config metodunda sahte (mock) veri** kullanıyor. Her mock bloğunun **hemen üstünde**, gerçek ortamda kullanılacak SELECT/INSERT ifadesi yorum satırı olarak zaten yazılmış durumda. Canlıya geçerken yapmanız gereken, her metotta:

1. `VALUE #( ... )` ile başlayan mock tabloyu (ve onu kullanan `READ TABLE`/atama satırlarını, gerekiyorsa) silmek,
2. Üstündeki yorumlanmış (`"` ile başlayan) gerçek SELECT/INSERT ifadesinin yorumunu kaldırmak ve sonucu aynı değişken adına atamak.

**Mock veri içeren ve değiştirilmesi gereken metotların tam listesi:**

| Sınıf | Metot | Ne değişecek |
|---|---|---|
| ZCL_ORDER_RISK_CONFIG | `get_mock_config` (get_config tarafından çağrılıyor) | `SELECT ... FROM zorder_risk_config` |
| ZCL_ORDER_RISK_CHECKER | `check_credit_limit` | `SELECT` KNKK (kredi limiti) ve BSID (açık bakiye) |
| ZCL_ORDER_RISK_CHECKER | `check_payment_perf` | BSID/BSAD üzerinden ortalama ödeme gecikmesi hesaplaması |
| ZCL_ORDER_RISK_CHECKER | `check_order_anomaly` | VBAK/VBAP join ile son 3 aylık ortalama sipariş tutarı |
| ZCL_ORDER_RISK_CHECKER | `check_stock` | `SELECT` MARD (depo stoku) |
| ZCL_ORDER_RISK_CHECKER | `check_blacklist` | `SELECT ... FROM zorder_blacklist` |
| ZCL_ORDER_RISK_CHECKER | `check_price_deviation` | VBAP/KONV join ile liste fiyatı |
| ZCL_ORDER_RISK_CHECKER | `check_customer_segment` | `SELECT` KNVV (müşteri segmenti/grubu) |
| ZCL_ORDER_RISK_LOGGER | `write_log` | `INSERT zorder_risk_log FROM TABLE @lt_logs` (şu an sadece MESSAGE ile simüle ediliyor) |
| ZCL_ORDER_RISK_LOGGER | `write_action_log` | `INSERT zorder_risk_log FROM @ls_log` |
| ZCL_ORDER_RISK_ALV | `get_log_data` | `SELECT ... FROM zorder_risk_log` |

**Ekstra not — ZCL_ORDER_RISK_NOTIFIER:** `resolve_recipient` metodu şu an sabit (hardcoded) e-posta adresleri döndürüyor (`sales.manager@company.com` vb.). Bu bir "mock veri bloğu" değil ama canlıya geçerken gerçekçi olması için VBAK → satış grubu → TVKGR → sorumlu kişi → ADR6 e-posta zincirini kullanan gerçek SELECT'lerle (metodun üstünde yorum olarak zaten yazılı) değiştirmeniz veya en azından adresleri bir config tablosundan okumanız önerilir.

Bu değişiklikleri yaparken her metodu tek tek değiştirip aktive edin ve test edin — hepsini aynı anda değiştirmek, bir hata olduğunda hangi SELECT'in sorunlu olduğunu bulmayı zorlaştırır.

---

## 8. Test Etme

1. `VA01` işlem kodunu açın, sipariş türü olarak standart bir tür (örn. `OR`) seçin, satış organizasyonu/dağıtım kanalı/bölümü girip Enter'a basın.
2. **CRITICAL senaryosu:** Müşteri numarası olarak `0000100002` girin (bu müşteri, ZORDER_BLACKLIST mock verisinde doğrudan kara listeye alınmış, ayrıca açık bakiyesi kredi limitinin %95'ine ulaşmış (herhangi bir sipariş limiti %100'ün üzerine taşıyor) ve ortalama ödeme gecikmesi 25 gün — CHECKER'ın mock verisiyle bu müşteri zaten CRITICAL çıkacak şekilde tasarlanmış). Herhangi bir malzeme ve miktar girip siparişi **kaydetmeye çalışın**. Beklenen sonuç: BAdI tetiklenir, toplam puan 86'nın üzerine çıkar ve `MESSAGE ... TYPE 'E'` nedeniyle sipariş **kaydedilemez**, ekranda kırmızı bir hata mesajı görürsünüz.
3. **HIGH senaryosu:** Müşteri `0000100001` ile aynı şekilde bir sipariş oluşturup kaydedin. Beklenen sonuç: sarı bir uyarı mesajı ("Order risk: HIGH...") görürsünüz ama sipariş **kaydedilir** (MESSAGE TYPE 'S' DISPLAY LIKE 'W' sadece bilgilendirir, engellemez).
4. **LOW senaryosu:** Müşteri `0000100000` ile bir sipariş oluşturup kaydedin. Beklenen sonuç: hiçbir risk mesajı görmeden sipariş sessizce kaydedilir.
5. `SE38` (veya doğrudan komut kutusuna `ZORDER_RISK_MONITOR`) ile raporu çalıştırın. Seçim ekranında tarih aralığını (varsayılan: son 30 gün) olduğu gibi bırakıp **Execute** (F8) tuşuna basın. Az önce kaydettiğiniz siparişlerin ALV tablosunda, risk seviyesine göre renklendirilmiş satırlar halinde göründüğünü doğrulayın.
6. Bir satır seçip araç çubuğundaki **Approve Order** veya **Reject Order** butonuna tıklayın; satırın "Status" (ACTION) sütununun güncellendiğini ve alt tarafta bir onay mesajı çıktığını doğrulayın.
7. Bir satır seçip **Show Check Details** butonuna tıklayın; açılan popup'ta o siparişin 7 kontrolünün tek tek puan/mesaj detayını görün.
8. **Export to Excel** butonunu deneyip bir dosya diyaloğunun açıldığını, kaydettiğiniz dosyanın sekme ile ayrılmış (tab-separated) veri içerdiğini kontrol edin.

---

## 9. Sorun Giderme

| Belirti | Olası Neden | Çözüm |
|---|---|---|
| Sınıf aktive edilemiyor, "Type ... is unknown" hatası | Bağımlı olduğu sınıf henüz aktive edilmemiş | Bölüm 3'teki sırayı takip edin; hata mesajındaki sınıf adını önce oluşturup aktive edin |
| Raporu çalıştırınca ekran boş geliyor, ALV görünmüyor | Screen 100'deki Custom Control'ün adı `ALV_CONTAINER` değil (yazım hatası ya da farklı isim) | SE51 → Layout → Custom Control'e çift tıklayıp Name alanını tam olarak `ALV_CONTAINER` yapın |
| BACK/EXIT/CANCEL tuşları çalışmıyor | STATUS100'de fonksiyon kodları eksik veya farklı yazılmış | SE41 ile STATUS100'ü açıp fonksiyon kodlarının tam olarak `BACK`, `EXIT`, `CANCEL` olduğunu kontrol edin |
| Sipariş kaydedilirken hiçbir risk mesajı çıkmıyor, BAdI hiç tetiklenmiyor | BAdI implementasyonu aktive edilmemiş, ya da yanlış BAdI/metot seçilmiş | SE19'da implementasyonun "Active" durumda olduğunu kontrol edin; SE18'de doğru BAdI'yi seçtiğinizi doğrulayın (item vs. header seviyesi) |
| "Table ZORDER_RISK_LOG unknown" veya benzeri runtime hatası | Z-tablo henüz aktive edilmemiş, ya da mock veriden gerçek SELECT'e geçtiniz ama tablo boş/yanlış isimde | SE11'de tablonun Active durumda olduğunu kontrol edin; SE16N ile tabloya birkaç test satırı girin |
| Risk e-postası gönderilmiyor, "Risk alert email could not be sent" mesajı | SCOT (SAP Connect) veya SMTP node yapılandırılmamış — bu, geliştirme sistemlerinde sık karşılaşılan normal bir durumdur | `SCOT` işlem koduyla bir SMTP node tanımlı olup olmadığını kontrol edin; portföy/test amaçlı sistemlerde bu adımı atlayabilir, sadece log ve dashboard'u test edebilirsiniz |
| SE19'da implementing class çakışması / yanlışlıkla ZCL_IM_ORDER_RISK'in üzerine yazıldı | Bölüm 4 Adım 4'teki uyarı atlanmış | SE19 implementasyonunu silip yeniden oluşturun, implementing class adını açıkça `ZCL_BADI_ORDER_RISK_IMPL` gibi farklı bir isim yapın |
| Ekran/program aktive edilirken "Screen 100 is not active" gibi bir uyarı | Program, screen, status, title'lardan biri unutulmuş | SE38'de Ctrl+F3 sonrası çıkan "Inactive Objects" listesindeki tüm satırları seçip birlikte aktive edin |

---

---

# ENGLISH

## 1. Overview

The Order Risk Engine is a risk evaluation engine that runs before a sales order is saved. It scores the order across 7 different checks (credit limit, payment performance, order anomaly, stock, blacklist, price deviation, customer segment) and, based on the total score, either lets the order pass with an informational warning or blocks it completely. Results are written to a log table, high-risk orders trigger an e-mail alert, and everything can be monitored through an ALV dashboard report.

We build things in a **specific order** for a simple reason: in ABAP, a class cannot be activated if it references another class that doesn't exist yet (you'll get a syntax error). So we'll first create the objects nothing depends on (tables, the ENTITY class), then the ones that depend on those, and finally the report and BAdI that tie everything together.

### Full list of objects to create

| # | Type | Object name | Where it's created |
|---|------|--------------|---------------------|
| 1 | Z-Table | ZORDER_RISK_LOG | SE11 |
| 2 | Z-Table | ZORDER_BLACKLIST | SE11 |
| 3 | Z-Table | ZORDER_RISK_CONFIG | SE11 |
| 4 | Class | ZCL_ORDER_RISK_ENTITY | SE24 |
| 5 | Class | ZCL_ORDER_RISK_CONFIG | SE24 |
| 6 | Class | ZCL_ORDER_RISK_CHECKER | SE24 |
| 7 | Class | ZCL_ORDER_RISK_NOTIFIER | SE24 |
| 8 | Class | ZCL_ORDER_RISK_LOGGER | SE24 |
| 9 | Class | ZCL_ORDER_RISK_ENGINE | SE24 |
| 10 | Class | ZCL_ORDER_RISK_ALV | SE24 |
| 11 | Class | ZCL_IM_ORDER_RISK (adapter target) | SE24 |
| 12 | BAdI Implementation | (named after the BAdI you find, e.g. ZIM_ORDER_RISK) | SE19 |
| 13 | Program (Report) | ZORDER_RISK_MONITOR | SE38 |
| 14 | Screen | Screen 100 (Custom Control: ALV_CONTAINER) | SE51 |
| 15 | GUI Status | STATUS100 | SE41 (or from within SE38) |
| 16 | Title | TITLE100 | SE41 (or from within SE38) |

In total: **3 Z-tables, 8 classes (spread across the core/badi/report folders), 1 BAdI implementation, 1 report, 1 screen, 1 GUI status, 1 title.**

---

## 2. Creating the Z-Tables (SE11)

### General concepts (read before proceeding)

- **Delivery Class A**: This marks the table as an "application table" — one that holds customer/business data, as opposed to SAP's own tables which use other delivery classes (S/C/G/E, etc.). For our own Z-tables you always choose **A**; otherwise the table might behave incorrectly during a system copy or upgrade.
- **Why is MANDT always the first key field?**: SAP is a multi-client system — several clients (e.g. 100, 200, 300) can live on the same server, and each client's data must stay isolated from the others. Without a MANDT field, data from one client could accidentally appear in another. That's why every client-dependent Z-table gets MANDT as its **first** key field.
- **What does "Activate" do?**: When you define a table in SE11 it's first saved only as a "draft" (inactive version). Activating (Ctrl+F3) turns that draft into a real database object (a physical table). An inactive table cannot be used in ABAP code — no SELECT, no INSERT.

### 2.1 Table: ZORDER_RISK_LOG

This table holds the permanent audit record of every risk evaluation and every approve/reject action.

| Field Name | Key? | Data Element / Type | Length | Description |
|---|---|---|---|---|
| MANDT | ✔ | MANDT | 3 | Client |
| LOG_ID | ✔ | SYSUUID_C | 32 | Unique identifier (UUID) per log row |
| VBELN | | VBELN | 10 | Sales order number |
| KUNNR | | KUNNR | 10 | Customer number |
| CHECK_NAME | | CHAR30 | 30 | Which check produced this row (e.g. CREDIT_LIMIT) |
| SCORE | | INT4 | 10 | Score awarded by this check |
| RISK_LEVEL | | CHAR10 | 10 | LOW / MEDIUM / HIGH / CRITICAL |
| MESSAGE | | CHAR100 | 100 | Descriptive message from the check |
| ACTION | | CHAR20 | 20 | RISK_EVALUATED / APPROVED / REJECTED |
| UNAME | | SYUNAME | 12 | User who performed the action |
| DATUM | | SYDATUM | 8 | Date |
| UZEIT | | SYUZEIT | 6 | Time |

**Step-by-step SE11 instructions:**

1. In the command box (the white box at the top-left of the SAP screen), type `SE11` and press Enter. You'll land on the "ABAP Dictionary: Initial Screen".
2. Make sure the "Database table" radio button is selected, type `ZORDER_RISK_LOG` into the name field, and click **Create**.
3. A pop-up will ask for a "Short Description" — type something like `Order Risk Evaluation Log` and press Enter.
4. On the **Delivery and Maintenance** tab, set **Delivery Class** to `A` (Application table, master and transaction data). This matters — leaving it blank triggers a warning during activation.
5. Switch to the **Fields** tab. On the first row, type `MANDT`, check the Key checkbox, and enter `MANDT` as the Data Element (pressing Enter auto-fills the length and description).
6. On the next row, type `LOG_ID`, check the Key checkbox, and enter `SYSUUID_C` as the Data Element.
7. Enter the remaining fields in the order shown above, **without** checking Key (VBELN, KUNNR, CHECK_NAME, SCORE, RISK_LEVEL, MESSAGE, ACTION, UNAME, DATUM, UZEIT). For each row, typing the Data Element and pressing Enter auto-fills the type/length; for fields like CHECK_NAME, RISK_LEVEL, MESSAGE, ACTION where you don't have a ready-made data element, you can type `CHAR` directly into the Data Type column and the length (30, 10, 100, 20) into the Length column.
8. Save (Ctrl+S). If prompted for a "Package", you can use `$TMP` (local object, no transport needed) for a portfolio project; on a real development system, use whichever Z package your team lead specifies.
9. Activate: press **Ctrl+F3** or click the "Activate" button (the yellow-red icon) in the toolbar. You should see an "Object activated" message at the bottom.

**Common mistake:** Forgetting the MANDT field, or forgetting to mark it as Key. This causes an activation error like "Table has no key fields" — fix it by going back to the Fields tab, adding MANDT, and checking its Key box.

### 2.2 Table: ZORDER_BLACKLIST

This table holds customer/material combinations that are forbidden or flagged as risky.

| Field Name | Key? | Data Element / Type | Length | Description |
|---|---|---|---|---|
| MANDT | ✔ | MANDT | 3 | Client |
| KUNNR | ✔ | KUNNR | 10 | Customer number (blank = all customers) |
| MATNR | ✔ | MATNR | 18 (ECC) / 40 (S/4HANA) | Material number (blank = all materials) |
| REASON | | CHAR100 | 100 | Reason for the blacklist entry |
| ACTIVE | | CHAR1 (abap_bool) | 1 | 'X' = active, blank = inactive |

**Step-by-step:**

1. `SE11` → type `ZORDER_BLACKLIST` in the name box → **Create**.
2. Short description: `Order Blacklist (Customer/Material)`.
3. Delivery Class = `A`.
4. On the Fields tab, mark MANDT, KUNNR, and MATNR all as **Key** (together the three form a composite key — a row must uniquely identify a "this customer + this material" combination).
5. Add the ACTIVE field WITHOUT the key flag, Data Type `CHAR`, Length `1`.
6. Save and activate (Ctrl+S, then Ctrl+F3).

**Note:** KUNNR or MATNR can be left blank (for example, to block a customer regardless of material, or a material regardless of customer). This matches the design of the `check_blacklist` method in ZCL_ORDER_RISK_CHECKER.

### 2.3 Table: ZORDER_RISK_CONFIG

This table holds the maximum score and threshold values for each check — this is the table that lets you tune risk behavior without touching code.

| Field Name | Key? | Data Element / Type | Length | Description |
|---|---|---|---|---|
| MANDT | ✔ | MANDT | 3 | Client |
| CHECK_NAME | ✔ | CHAR30 | 30 | Check name (e.g. CREDIT_LIMIT) |
| MAX_SCORE | | INT4 | 10 | Maximum score this check can award |
| THRESHOLD_LOW | | INT4 | 10 | Low-risk threshold |
| THRESHOLD_HIGH | | INT4 | 10 | High-risk threshold |
| ACTIVE | | CHAR1 (abap_bool) | 1 | 'X' = this check runs, blank = skipped |

**Step-by-step:**

1. `SE11` → `ZORDER_RISK_CONFIG` → **Create**.
2. Short description: `Order Risk Check Configuration`.
3. Delivery Class = `A`.
4. Mark MANDT and CHECK_NAME as **Key**. Add MAX_SCORE, THRESHOLD_LOW, THRESHOLD_HIGH, ACTIVE without the key flag.
5. Save and activate.

Once all three tables are done, verify (via SE11 → Utilities → Where-Used, or in the SE80 package tree) that all three show as "Active".

---

## 3. Creating the ABAP Classes (SE24)

### Why this order?

The order below follows the dependency chain: each class references the classes listed before it. For example, `ZCL_ORDER_RISK_CHECKER` uses types from `ZCL_ORDER_RISK_CONFIG` and `ZCL_ORDER_RISK_ENTITY`; if those two aren't active first, CHECKER won't compile.

1. **ZCL_ORDER_RISK_ENTITY** — depends on nothing; holds all shared TYPES and CONSTANTS (file: `src/core/ZCL_ORDER_RISK_ENTITY.abap`)
2. **ZCL_ORDER_RISK_CONFIG** — depends on ENTITY's types (file: `src/core/ZCL_ORDER_RISK_CONFIG.abap`)
3. **ZCL_ORDER_RISK_CHECKER** — depends on ENTITY and CONFIG (file: `src/core/ZCL_ORDER_RISK_CHECKER.abap`)
4. **ZCL_ORDER_RISK_NOTIFIER** — depends on ENTITY (file: `src/core/ZCL_ORDER_RISK_NOTIFIER.abap`)
5. **ZCL_ORDER_RISK_LOGGER** — depends on ENTITY (file: `src/core/ZCL_ORDER_RISK_LOGGER.abap`)
6. **ZCL_ORDER_RISK_ENGINE** — calls CHECKER, NOTIFIER, and LOGGER, so all three must be active first (file: `src/badi/ZCL_ORDER_RISK_ENGINE.abap`)
7. **ZCL_ORDER_RISK_ALV** — depends on ENTITY and LOGGER, draws the dashboard (file: `src/report/ZCL_ORDER_RISK_ALV.abap`)
8. **ZCL_IM_ORDER_RISK** — calls ENGINE, should be activated last (file: `src/badi/ZCL_IM_ORDER_RISK.abap`)

### The steps you repeat for every class

For each class, follow these steps:

1. In the command box, type `SE24` and press Enter.
2. Make sure "Object type" is set to **Class**, and type the full class name (e.g. `ZCL_ORDER_RISK_ENTITY`) into "Object name".
3. Click **Create**. In the pop-up, keep "Class Type" as `Class` (the default), enter a short description (e.g. `Order Risk - Common Types and Constants`), and press Enter.
4. At this point SAP opens the visual Class Builder screen (which wants you to add methods one by one by hand). Instead, we're going to paste the ready-made code directly: from the top menu, go to **Utilities → Convert to Source Code Editor** (on some versions: **Utilities → Source Code-Based Editing**). This switches the screen to a single plain-text editor where you see both the `CLASS ... DEFINITION` and `CLASS ... IMPLEMENTATION` blocks together.
5. Select and delete the existing template in the editor (Ctrl+A, Delete), then copy and paste the **entire contents** of the corresponding file (from `src/core/...`, `src/badi/...`, or `src/report/...`).
6. Save (Ctrl+S). If asked for a package, choose `$TMP` or your project's package.
7. Activate: **Ctrl+F3**. If there are no errors, you'll see "Object activated" at the bottom. If there's an error (e.g. "Type ZCL_ORDER_RISK_CONFIG is unknown"), suspect that the class it depends on hasn't been activated yet — double-check the next step.

**Important note:** Take each file from its own folder — 5 classes live in `core/` (ENTITY, CONFIG, CHECKER, NOTIFIER, LOGGER), 2 classes live in `badi/` (ENGINE, ZCL_IM_ORDER_RISK), and 1 class lives in `report/` (ALV). Pasting the wrong file into the wrong class will cause a compile error.

**Common mistake:** Trying to activate the classes in a random order. ABAP refuses to activate code that references a type not yet defined (e.g. if a dependent class doesn't exist yet). Look up the class name mentioned in the error message and make sure you've created it first.

---

## 4. Finding and Implementing the BAdI (SE18 / SE19)

This is the **most critical and most detailed** section of the guide — please don't rush it.

### What is a BAdI? (plain-language explanation)

A BAdI (Business Add-In) is an official "hook" that SAP builds into its standard programs, letting you plug in your own code without modifying SAP's original code. At a specific moment during a process (for example, while a sales order is being saved), SAP automatically calls a method on a class you wrote. This lets us insert our own risk check into the order-save flow without touching SAP's original save logic. It's also upgrade-safe: even if SAP changes its underlying code, your BAdI implementation generally keeps working.

### Step 1 — Use SE18 to search for the BAdI definition

Type `SE18` in the command box and press Enter. **SE18 is for SEARCHING/VIEWING BAdI definitions** — you do NOT create your own implementation (your own code) here, you're just checking "does this BAdI exist, and if so, what methods does it have?"

### Step 2 — Searching for the sales order save BAdI

The exact name of this BAdI depends on your SAP version, so try the following candidates **in order**:

1. `BADI_SD_SALES_ITEM` — the current item-level BAdI on S/4HANA.
2. `BADI_SALES_ORDER_SAVE` — the save BAdI on newer S/4HANA releases.
3. `SD_SALES_DOCUMENT_SAVE` — the classic ECC BAdI.

Try each one by typing it into the name field on the SE18 screen and clicking **Display** (the glasses icon). If the BAdI exists, the definition's detail screen opens (showing the Interface and its methods). If it doesn't exist, you'll get an error like "Enhancement spot &1 does not exist" — in that case, try the next candidate in the list.

**How do you know it exists?** If the Display screen opens without error and you see at least one method (e.g. something like `SAVE_DOCUMENT_PREPARE`) under "Interfaces" on the left, that BAdI is present on your system.

### Step 3 — If none exist: the classic user exit (MV45AFZZ)

Some older ECC systems don't have any of the BAdIs above. In that case, fall back to the classic user exit mechanism:

- Use transaction `SMOD` to look up `VA00001` (the enhancement that holds the sales order user exits).
- Use transaction `CMOD` to create a "project", assign it to that enhancement, and activate it.
- Your actual code goes inside the `USEREXIT_SAVE_DOCUMENT_PREPARE` form routine, in the `MV45AFZZ` include.

This approach is older and less flexible than a BAdI (multiple teams editing the same include risks conflicts), but it's still the only option on many ECC systems. It's out of scope for this guide's detailed steps — the underlying logic is the same: you write the adapter code (Step 5 below) inside that form routine instead.

### Step 4 — Use SE19 to CREATE an implementation

Type `SE19` in the command box. This time we're **creating an implementation** (wiring in our own code).

1. Select "New Implementation" (or "Create").
2. In the "Enhancement Spot" or "BAdI Definition" box, enter the BAdI name you found in Step 2 (e.g. `BADI_SD_SALES_ITEM`) and press Enter.
3. In the "Implementation" name box, enter your own implementation name, e.g. `ZIM_ORDER_RISK`, and press Enter.
4. SAP will automatically propose an "Implementing Class" name (usually something close to your implementation name, e.g. `ZCL_IM_ORDER_RISK`).
   **⚠️ VERY IMPORTANT:** Do **not** accept this proposed name — the project already has a class called `ZCL_IM_ORDER_RISK` (the adapter target) that you created in SE24 in Section 3. If the names collide, activation will fail or you'll overwrite the wrong class. Instead, explicitly type a different name into the implementing class field, e.g. `ZCL_BADI_ORDER_RISK_IMPL`.
5. Press Enter to continue; SAP creates the implementation and the (empty skeleton) implementing class.
6. Save (package `$TMP` or your project package).

### Step 5 — Pasting the adapter code

Double-click the relevant method of the newly created `ZCL_BADI_ORDER_RISK_IMPL` class (visible under the "Interface" or "Methods" tab in the SE19 screen) — this takes you to the code editor. Paste the adapter code shown in the header comment of `ZCL_IM_ORDER_RISK.abap`, adapting it to your BAdI's actual parameter names:

```abap
METHOD if_ex_badi_sd_sales_item~save_document_prepare.

  DATA(lo_risk) = NEW zcl_im_order_risk( ).

  DATA(lt_items) = VALUE zcl_order_risk_entity=>ty_order_items(
    FOR ls_vbap IN it_vbap
    ( matnr = ls_vbap-matnr
      menge = ls_vbap-kwmeng
      netpr = ls_vbap-netpr
      kpein = ls_vbap-kpein
      werks = ls_vbap-werks ) ).

  lo_risk->on_order_save(
    iv_vbeln = is_vbak-vbeln
    iv_kunnr = is_vbak-kunnr
    it_items = lt_items ).

ENDMETHOD.
```

This code has exactly one job: convert whatever VBAK/VBAP data (or your BAdI's IMPORTING/CHANGING parameters) SAP hands you into the simple types `ZCL_IM_ORDER_RISK` expects (`ty_order_items`), and call `on_order_save()`. The method name, parameter names, and table names will vary depending on which actual BAdI you found — so don't paste this verbatim, adapt it to the real interface of the BAdI you're implementing.

### Step 6 — Activate

Use `Ctrl+F3` to activate both the method and the implementation itself (there's also an Activate button on the main SE19 screen). After activation, the implementation should show as "Active" — an inactive implementation is never called by SAP.

### Common mistakes

- **Choosing the wrong level (item vs. header):** `BADI_SD_SALES_ITEM` runs at item level and usually fires multiple times (once per item); `BADI_SALES_ORDER_SAVE` runs once at document (header) level. Picking the wrong one can cause `on_order_save()` to be called multiple times or with incomplete data. Always read the BAdI's documentation (the "Documentation" button on the SE18 screen).
- **Method signature mismatch:** The `it_vbap`, `is_vbak` parameter names in the adapter snippet are illustrative — your actual BAdI's IMPORTING/CHANGING parameters may be named differently. When you double-click the method in SE19, the real parameter list appears at the top; adjust your code to match it.
- **Forgetting to activate the implementation:** Even if the code compiles cleanly, if the implementation itself is left "Inactive" the BAdI never fires. If you save an order and see no risk messages at all, this should be your first thing to check.

---

## 5. Creating the Report and Screen (SE38 / SE51)

### 5.1 Creating the program with SE38

1. Type `SE38` in the command box, enter `ZORDER_RISK_MONITOR` as the program name, and click **Create**.
2. In the "Program Attributes" pop-up: set Title = `Order Risk Dashboard`, Type = `Executable Program`, Status = `Test Program` (optional), then save.
3. When the code editor opens, paste the entire contents of `src/report/ZORDER_RISK_MONITOR.abap`.
4. Save (Ctrl+S) but **don't activate yet** — the code references Screen 100 (`CALL SCREEN 100`) and `STATUS100`/`TITLE100`, none of which exist yet. We need to build the screen and status first, then activate everything together.

### 5.2 Creating Screen 100 with SE51 (Screen Painter)

1. Type `SE51` in the command box. Enter program `ZORDER_RISK_MONITOR`, screen number `100`, and click **Create**.
2. On the Screen Attributes screen, enter Short description = `Order Risk Dashboard Screen`, leave Screen Type = `Normal`, and save.
3. Click the **Layout** button (the graphical editor). On the blank canvas that opens, drag a **Custom Control** element from the element palette on the left onto a large portion of the screen (ideally close to the full screen, leaving a small margin at the top).
4. Double-click the custom control you placed. In the properties pop-up, type exactly `ALV_CONTAINER` into the **Name** field. **This name must match letter-for-letter** — the `display()` method of `ZCL_ORDER_RISK_ALV` creates its `cl_gui_custom_container` object using the literal `container_name = 'ALV_CONTAINER'`. If the names don't match, the ALV never appears — you'll just see a blank screen.
5. Leave the Layout editor (Back) to return to the main Screen Painter screen.
6. Switch to the **Flow Logic** tab. You'll see the PBO (Process Before Output) and PAI (Process After Input) blocks; SAP usually proposes a line like `MODULE STATUS_0100.` by default. Edit the content so it reads exactly:

```abap
PROCESS BEFORE OUTPUT.
  MODULE status_0100.
  MODULE display_alv_0100.

PROCESS AFTER INPUT.
  MODULE user_command_0100.
```

7. Save, but don't activate yet (activation will warn/fail while the GUI Status and Title are still missing — we'll finish those and activate everything together at the end).

### 5.3 Creating the GUI Status (STATUS100)

1. With the `ZORDER_RISK_MONITOR` program open in SE38 (in Change mode), go to **Goto → PF-Status...** from the top menu (on some versions you'll instead be directed to transaction `SE41` directly, where you enter the program name plus the status name).
2. Enter `STATUS100` as the status name and press Enter; answer Yes to "does not exist, create?".
3. In the Menu Painter screen that opens, add three function codes under "Function Keys" or "Standard Toolbar":
   - `BACK` (typically mapped to F3, back-arrow icon)
   - `EXIT` (typically Shift+F3)
   - `CANCEL` (typically F12, red X icon)
4. Make sure these three codes are spelled exactly `BACK`, `EXIT`, and `CANCEL` — because the `user_command_0100` module in `ZORDER_RISK_MONITOR` compares `sy-ucomm` against exactly these three strings.
5. Save and activate.

### 5.4 Creating the Title (TITLE100)

1. In the same program, go to **Goto → Titles...** (or Text Elements → Titles).
2. Enter Title name `TITLE100`, text `Order Risk Dashboard`.
3. Save and activate.

### 5.5 Maintaining the Text Symbols

1. Go to **Goto → Text Elements → Text Symbols** (or click the Text Elements icon from the program attributes screen in SE38).
2. Enter the following two rows:

   | Sym | Text |
   |-----|------|
   | 001 | Date Range |
   | 002 | Risk Filters |

3. Save and activate. These texts will appear as the frame titles for the `BLOCK b01`/`b02` sections on the selection screen.

### 5.6 Activating everything together

Now that the program, screen, status, and title are all in place, go back to `SE38` and activate `ZORDER_RISK_MONITOR` with **Ctrl+F3**. If an "Inactive Objects" list pops up (listing the program + screen 100 + status + title together), **select all of them** and activate together. Once there are no errors, you can run the report directly from `SE38` via **Direct Processing** (F8).

---

## 6. Entering Configuration Data

### 6.1 Filling ZORDER_RISK_CONFIG

Type `SE16N` in the command box (or use `SM30` — since ZORDER_RISK_CONFIG has no dedicated maintenance view yet, SM30 may warn about generic table maintenance; for this portfolio project, SE16N is the simplest route). In `SE16N`, enter `ZORDER_RISK_CONFIG` as the table name and press Enter, then click the **pencil/edit** icon on the toolbar to switch into row-entry mode (data entry in SE16N generally requires the `&SAP_EDIT` system parameter; if that's not available, your system should have a maintenance view defined via `SM30` instead — check with a Basis/ABAP colleague on your team if needed).

Enter the following 7 rows, using the same default values already hard-coded in the `ZCL_ORDER_RISK_CONFIG` class's mock data:

| CHECK_NAME | MAX_SCORE | THRESHOLD_LOW | THRESHOLD_HIGH | ACTIVE |
|---|---|---|---|---|
| CREDIT_LIMIT | 25 | 10 | 20 | X |
| PAYMENT_PERF | 20 | 8 | 15 | X |
| ORDER_ANOMALY | 15 | 6 | 12 | X |
| STOCK | 15 | 6 | 12 | X |
| BLACKLIST | 25 | 0 | 25 | X |
| PRICE_DEV | 10 | 4 | 8 | X |
| CUSTOMER_SEG | 10 | 4 | 8 | X |

These 7 rows' MAX_SCORE values sum to 120. The total risk score is then classified using these thresholds (these live as constants in `ZCL_ORDER_RISK_ENTITY`, not in the config table): 31 and above = MEDIUM, 61 and above = HIGH, 86 and above = CRITICAL.

### 6.2 Adding rows to ZORDER_BLACKLIST

Similarly, using `SE16N` (or `SM30`), add example rows to `ZORDER_BLACKLIST`:

| KUNNR | MATNR | REASON | ACTIVE |
|---|---|---|---|
| 0000100002 | (blank) | Customer under investigation | X |
| (blank) | MAT100030 | Restricted material | X |

The first row means "this customer is blocked regardless of what material they order" (MATNR blank). The second row means "this material is blocked regardless of which customer orders it" (KUNNR blank).

### 6.3 Why this matters

The entire point of these two tables is to let you change risk behavior **without changing code**. If you want to disable a check entirely, set `ACTIVE` to blank. If you want to tighten a threshold, lower `THRESHOLD_HIGH`. If you want to flag a new risky customer, add a row. None of this requires opening the ABAP editor — this is the whole idea behind config-driven design.

---

## 7. Switching from Mock Data to Real Tables

Right now, the project uses **fake (mock) data in every check and config method** so it can be tested without needing a live SAP system. The real SELECT/INSERT statement that should run in production is already written as a **comment directly above** each mock block. To go live, in each method you need to:

1. Delete the `VALUE #( ... )` mock table (and any `READ TABLE`/assignment lines built purely around it, if applicable), and
2. Uncomment the real SELECT/INSERT statement above it (the lines starting with `"`), assigning the result to the same variable name the mock used.

**Full list of methods containing mock data that needs replacing:**

| Class | Method | What changes |
|---|---|---|
| ZCL_ORDER_RISK_CONFIG | `get_mock_config` (called by `get_config`) | `SELECT ... FROM zorder_risk_config` |
| ZCL_ORDER_RISK_CHECKER | `check_credit_limit` | `SELECT` on KNKK (credit limit) and BSID (open balance) |
| ZCL_ORDER_RISK_CHECKER | `check_payment_perf` | Average payment delay computed from BSID/BSAD |
| ZCL_ORDER_RISK_CHECKER | `check_order_anomaly` | VBAK/VBAP join for the trailing 3-month average order value |
| ZCL_ORDER_RISK_CHECKER | `check_stock` | `SELECT` on MARD (plant stock) |
| ZCL_ORDER_RISK_CHECKER | `check_blacklist` | `SELECT ... FROM zorder_blacklist` |
| ZCL_ORDER_RISK_CHECKER | `check_price_deviation` | VBAP/KONV join for the list price |
| ZCL_ORDER_RISK_CHECKER | `check_customer_segment` | `SELECT` on KNVV (customer segment/group) |
| ZCL_ORDER_RISK_LOGGER | `write_log` | `INSERT zorder_risk_log FROM TABLE @lt_logs` (currently just simulated via MESSAGE) |
| ZCL_ORDER_RISK_LOGGER | `write_action_log` | `INSERT zorder_risk_log FROM @ls_log` |
| ZCL_ORDER_RISK_ALV | `get_log_data` | `SELECT ... FROM zorder_risk_log` |

**Extra note — ZCL_ORDER_RISK_NOTIFIER:** the `resolve_recipient` method currently returns hardcoded e-mail addresses (`sales.manager@company.com`, etc.). This isn't a "mock data block" in the same sense, but for a realistic production setup you should replace it with the real SELECT chain (VBAK → sales group → TVKGR → responsible person → ADR6 e-mail, already sketched as comments above the method) or, at minimum, read the addresses from a config table.

Change and activate one method at a time, testing as you go — changing everything at once makes it much harder to tell which SELECT is the problem if something breaks.

---

## 8. Testing

1. Open transaction `VA01`, pick a standard order type (e.g. `OR`), enter sales organization / distribution channel / division, and press Enter.
2. **CRITICAL scenario:** Enter customer number `0000100002` (this customer is directly blacklisted in the ZORDER_BLACKLIST mock data, and also has an open balance already at 95% of its credit limit (so any order pushes it over 100%) and a 25-day average payment delay in the CHECKER's mock data — it's specifically designed to come out CRITICAL). Add any material and quantity, then **try to save**. Expected result: the BAdI fires, the total score exceeds 86, and the order **cannot be saved** — a `MESSAGE ... TYPE 'E'` produces a red error message on screen.
3. **HIGH scenario:** Create and save a similar order for customer `0000100001`. Expected result: a yellow warning message appears ("Order risk: HIGH...") but the order **does save** (`MESSAGE TYPE 'S' DISPLAY LIKE 'W'` only informs, it doesn't block).
4. **LOW scenario:** Create and save an order for customer `0000100000`. Expected result: the order saves silently with no risk message.
5. Run the report via `SE38` (or by typing `ZORDER_RISK_MONITOR` directly into the command box). On the selection screen, leave the date range at its default (last 30 days) and press **Execute** (F8). Confirm that the orders you just saved appear in the ALV grid as color-coded rows matching their risk level.
6. Select a row and click the **Approve Order** or **Reject Order** toolbar button; confirm the row's "Status" (ACTION) column updates and a confirmation message appears at the bottom.
7. Select a row and click **Show Check Details**; confirm the popup shows the score/message breakdown for each of that order's 7 checks.
8. Try the **Export to Excel** button and confirm a file dialog opens and the saved file contains tab-separated data.

---

## 9. Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Class won't activate, "Type ... is unknown" error | A class it depends on hasn't been activated yet | Follow the order in Section 3; create and activate the class named in the error message first |
| Report runs but the screen is blank, no ALV appears | The Custom Control on Screen 100 isn't named exactly `ALV_CONTAINER` (typo or different name) | In SE51 → Layout, double-click the Custom Control and set Name to exactly `ALV_CONTAINER` |
| BACK/EXIT/CANCEL buttons don't do anything | Function codes in STATUS100 are missing or misspelled | Open STATUS100 in SE41 and verify the function codes are exactly `BACK`, `EXIT`, `CANCEL` |
| No risk message appears when saving an order, BAdI never fires | The BAdI implementation isn't active, or the wrong BAdI/method was chosen | Check that the implementation shows "Active" in SE19; verify you picked the correct BAdI in SE18 (item vs. header level) |
| Runtime error like "Table ZORDER_RISK_LOG unknown" | The Z-table hasn't been activated, or you switched from mock data to a real SELECT but the table is empty/misnamed | Confirm the table shows Active in SE11; add a few test rows via SE16N |
| Risk e-mail doesn't send, "Risk alert email could not be sent" message | SCOT (SAP Connect) or an SMTP node isn't configured — this is common and normal on dev/test systems | Check whether an SMTP node is configured via transaction `SCOT`; for a portfolio/test system you can skip this and just verify the log and dashboard instead |
| Implementing class collision in SE19 / ZCL_IM_ORDER_RISK got accidentally overwritten | The warning in Section 4, Step 4 was skipped | Delete and recreate the SE19 implementation, explicitly naming the implementing class something different, e.g. `ZCL_BADI_ORDER_RISK_IMPL` |
| Warning like "Screen 100 is not active" when activating | One of program/screen/status/title was forgotten | In SE38, after Ctrl+F3, select every row in the "Inactive Objects" list that appears and activate them all together |