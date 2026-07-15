# Technical Architecture — Order Risk Engine

## 1. Why it's built this way

The guiding idea is the same one behind the rest of this portfolio — one class, one job — but this project adds a second constraint on top: the thing that decides "should this order actually be blocked" is a BAdI, and BAdIs are a genuinely hostile place to put business logic. You can't step through them easily, they run inside someone else's transaction, and a bug that raises the wrong exception at the wrong moment can stop a sales order from saving in production. So the design pulls every piece of judgment *out* of the BAdI and into plain classes that can be built, called, and tested completely on their own.

- **Separation of concerns** — evaluation (`ZCL_ORDER_RISK_CHECKER`), notification (`ZCL_ORDER_RISK_NOTIFIER`), audit logging (`ZCL_ORDER_RISK_LOGGER`), orchestration (`ZCL_ORDER_RISK_ENGINE`), presentation (`ZCL_ORDER_RISK_ALV`), and the BAdI entry point (`ZCL_IM_ORDER_RISK`) are six different classes, not six methods on one class. Scoring a customer's payment history has nothing to do with sending an e-mail or drawing an ALV grid, so none of them know the others exist beyond the one call each needs to make.
- **The engine is deliberately inert** — `ZCL_ORDER_RISK_ENGINE->EVALUATE_ORDER` scores the order, writes the audit log, sends the alert if one is warranted, and hands a `ty_risk_result` back. That's it. It never raises an exception and it never blocks anything — read the comment at the top of the class, it says so explicitly. That's not an oversight, it's the entire point: the moment the engine started deciding *what to do* about a CRITICAL result, it would only be safely callable from the one place that wanted that exact behavior. Because it stays a pure "evaluate and report" service instead, the same `NEW zcl_order_risk_engine( )->evaluate_order( ... )` call works from a nightly batch job scoring yesterday's orders, from a report re-checking a customer's whole open order book, from an ABAP Unit test asserting on the returned score, or from the BAdI itself — and none of those callers have to work around behavior that only makes sense for one of the others.
- **Config-driven scoring** — none of the seven checks in `ZCL_ORDER_RISK_CHECKER` hardcode a weight or a threshold. Every one of them takes an `is_config` structure (`max_score`, `threshold_low`, `threshold_high`, `active`) sourced from `ZCL_ORDER_RISK_CONFIG->GET_CONFIG`, which is meant to read `ZORDER_RISK_CONFIG`. If credit exposure turns out to matter more than the initial weighting assumed, that's a table maintenance change, not a transport of `ZCL_ORDER_RISK_CHECKER`. `GET_CONFIG` also filters out anything with `active = abap_false`, so a check can be switched off entirely — including from the scoring loop, not just hidden from a report — without touching code.
- **Swappable persistence** — every mock data block in this project (credit exposure, payment delay, order history, stock, blacklist, price lists, customer segment, and the config and log tables themselves) has the real `SELECT`/`INSERT` written as a comment directly above it. `check_credit_limit`, for instance, has `SELECT SINGLE klimk FROM knkk` and `SELECT SUM( dmbtr ) FROM bsid` commented right above the `VALUE #( ... )` literal that stands in for them today. Going live is a matter of deleting the mock block and uncommenting the SELECT in each of those handful of spots — nothing about the checker's control flow, the config class, or the engine changes.
- **Audit by design** — `ZCL_ORDER_RISK_LOGGER` has exactly two public methods, `write_log` (one row per check, per evaluation) and `write_action_log` (one row per manual Approve/Reject click), and both of them only ever `INSERT`. There is no `update_log` method and nothing in this codebase ever rewrites a `ZORDER_RISK_LOG` row. That's intentional: an audit trail that can be edited after the fact isn't an audit trail. If a CRITICAL order later gets approved by a manager, that approval is a *new* row layered on top of the evaluation rows, not a correction to them — the dashboard groups them back together per order (see §7), but the underlying log always shows both what the engine found and what a human decided to do about it.

## 2. Who does what

| Class | Layer | Responsibility |
|---|---|---|
| `ZCL_ORDER_RISK_ENTITY` | Domain types | Shared structures and constants (`ty_order_item`, `ty_risk_check`, `ty_risk_result`, `ty_risk_config`, `ty_risk_log`, `ty_blacklist`, plus risk-level, color, score-threshold, action, and check-name constants). Never instantiated — `CREATE PRIVATE`. |
| `ZCL_ORDER_RISK_CONFIG` | Configuration | Reads the scoring configuration (weight and thresholds per check) that would live in `ZORDER_RISK_CONFIG`. |
| `ZCL_ORDER_RISK_CHECKER` | Domain logic | Runs the seven weighted risk checks against an order, sums their scores, and maps the total to a risk level. |
| `ZCL_ORDER_RISK_NOTIFIER` | Notification | Sends the risk-alert e-mail, but only for HIGH and CRITICAL results. |
| `ZCL_ORDER_RISK_LOGGER` | Audit | Writes the audit trail — one row per check per evaluation, plus one row per manual approve/reject action. |
| `ZCL_ORDER_RISK_ENGINE` | Orchestration | Calls checker → logger → notifier in sequence and returns the result. Never raises, never blocks. |
| `ZCL_IM_ORDER_RISK` | BAdI entry point | The one place that turns a risk level into a save-blocking decision. |
| `ZCL_ORDER_RISK_ALV` | Presentation | Dashboard: reads the audit log, groups it per sales order, renders it as a color-coded ALV grid with Approve/Reject/Details/Export actions. |
| `ZORDER_RISK_MONITOR` | Entry point | Executable report: selection screen (date range, risk level, customer), screen 100 flow, instantiates the ALV class. |

## 3. How a request flows through it

**BAdI side — an order gets saved in VA01:**

```
VA01 save
    │
    ▼
BAdI adapter (SD_SALES_DOCUMENT_SAVE / BADI_SD_SALES_ITEM / user exit — see §5 and the
class header of ZCL_IM_ORDER_RISK for why this step is deliberately not fixed)
    │  maps VBAK/VBAP into ty_order_items
    ▼
ZCL_IM_ORDER_RISK->on_order_save( iv_vbeln, iv_kunnr, it_items )
    │
    ▼
ZCL_ORDER_RISK_ENGINE->evaluate_order( )
    │
    ├─► ZCL_ORDER_RISK_CHECKER->evaluate( )
    │         ├─ check_credit_limit()      ~ KNKK + BSID
    │         ├─ check_payment_perf()      ~ BSID/BSAD average overdue days
    │         ├─ check_order_anomaly()     ~ VBAK/VBAP 3-month average
    │         ├─ check_stock()             ~ MARD available stock
    │         ├─ check_blacklist()         ~ ZORDER_BLACKLIST
    │         ├─ check_price_deviation()   ~ VBAP/KONV list price
    │         ├─ check_customer_segment()  ~ KNVV
    │         └─ calculate_risk_level()    → total_score, risk_level
    │
    ├─► ZCL_ORDER_RISK_LOGGER->write_log( )      → one audit row per check
    │
    └─► ZCL_ORDER_RISK_NOTIFIER->send_risk_alert( )   → e-mail, only if HIGH/CRITICAL
    │
    ▼  (result returned to the BAdI)
ZCL_IM_ORDER_RISK
    │
    ▼
CASE ls_result-risk_level.
    LOW      → no action, order saves silently
    MEDIUM   → MESSAGE TYPE 'S' DISPLAY LIKE 'W' (informational)
    HIGH     → MESSAGE TYPE 'S' DISPLAY LIKE 'W' (informational, manager already notified by e-mail)
    CRITICAL → MESSAGE TYPE 'E'  →  save is blocked
```

**Dashboard side — someone opens the monitor to review past evaluations:**

```
ZORDER_RISK_MONITOR (selection screen: date range / risk level / customer)
    │
    ▼
CALL SCREEN 100
    │
    ▼
ZCL_ORDER_RISK_ALV->display( iv_date_from, iv_date_to, iv_risk_level, iv_kunnr )
    │
    ├─ get_log_data()          ~ SELECT * FROM ZORDER_RISK_LOG WHERE ...
    ├─ build_dashboard_data()  → GROUP BY vbeln, one row per order (not per check)
    ├─ build_fieldcatalog() / build_layout()   → ROW_COLOR-driven coloring
    └─ CL_GUI_ALV_GRID->set_table_for_first_display()

User selects a row and clicks a toolbar button
    │
    ▼
on_user_command( e_ucomm )
    ├─ APPROVE       → write_action_log( ..., gc_action-approved )  → row updated in place
    ├─ REJECT        → write_action_log( ..., gc_action-rejected )  → row updated in place
    ├─ SHOW_DETAILS  → show_check_details( vbeln )  → CL_SALV_TABLE popup, per-check breakdown
    └─ EXCEL_EXPORT  → export_to_excel( )  → tab-separated download of mt_alv_data
```

## 4. The seven checks and scoring

| Check | Looks at (real tables) | Max score | Logic |
|---|---|---|---|
| `CREDIT_LIMIT` | `KNKK` credit limit + `BSID` open items | 25 | Usage = (open balance + this order) / credit limit. ≥100% → full score; ≥90% → 70%; ≥80% → 40%; below that → 0. |
| `PAYMENT_PERF` | `BSID`/`BSAD` average days overdue | 20 | Above `threshold_high` → full score; between `threshold_low` and `threshold_high` → linear ramp; below `threshold_low` → 0. |
| `ORDER_ANOMALY` | `VBAK`/`VBAP` 3-month average order value | 15 | Order value vs. that customer's average. >200% of average → full score; ≥100%+`threshold_high` → 60%; ≥100%+`threshold_low` → 30%; otherwise 0. |
| `STOCK` | `MARD` available stock vs. ordered quantity | 15 | % of order lines with insufficient stock. 100% short → full score; above `threshold_high` → 60%; above `threshold_low` → 30%; otherwise 0. |
| `BLACKLIST` | `ZORDER_BLACKLIST` (customer and/or material restrictions) | 25 | Binary — any active match on customer, material, or the combination → full score; otherwise 0. |
| `PRICE_DEV` | Order price vs. list price (`VBAP`/`KONV`) | 10 | Discount % above `threshold_high` → full score; above `threshold_low` → 50%; otherwise 0. |
| `CUSTOMER_SEG` | Customer segment (would be `KNVV`-derived) | 10 | Segment C → full score; segment B → 50%; segment A → 0. |

The seven scores are summed into `total_score`, and that number is mapped to a risk level by `gc_score_threshold` in `ZCL_ORDER_RISK_ENTITY`:

| Score | Risk level |
|---|---|
| 0 – 30 | LOW |
| 31 – 60 | MEDIUM |
| 61 – 85 | HIGH |
| 86+ | CRITICAL |

Both the per-check weights and the score-to-level cutoffs come from configuration, not from numbers buried in `ZCL_ORDER_RISK_CHECKER`: the weights (`max_score`, `threshold_low`, `threshold_high`) come from `ZCL_ORDER_RISK_CONFIG`, and the four score bands come from `zcl_order_risk_entity=>gc_score_threshold`. Retuning how sensitive the whole engine is — say, deciding that 61 is too aggressive a cutoff for HIGH — is a constant or a config-table change, not a rewrite of the scoring loop.

## 5. The block decision — why it lives in the BAdI, not the engine

`ZCL_ORDER_RISK_ENGINE->evaluate_order` returns a `ty_risk_result` and stops there. It is `ZCL_IM_ORDER_RISK->on_order_save` that runs the `CASE` on `risk_level` and, only for CRITICAL, executes `MESSAGE ... TYPE 'E'`. That's the one line in the entire codebase that actually stops a save — `MESSAGE TYPE 'E'` raised from inside a BAdI aborts the enclosing update the same way a classic validation error would.

The reason `RAISE`/`MESSAGE TYPE 'E'` is kept strictly out of the engine is that "block the save" is a meaning that only exists inside a BAdI. A batch job re-scoring last month's orders doesn't want a CRITICAL result to throw an exception that kills the job — it wants the result back so it can write a report. A unit test asserting `total_score = 86` doesn't want to catch an exception to get at the number it's testing. Even inside VA01, blocking is really a *policy* choice ("do we stop CRITICAL orders, or just HIGH-and-above, or none at all") that's more natural to change in one small `CASE` statement than to change by editing the class every other caller also depends on. Keeping the engine a passive reporter and putting the one consequential `MESSAGE TYPE 'E'` in the thinnest possible layer on top of it is what lets every other consumer treat the engine as safe to call.

## 6. The three Z-tables

- **`ZORDER_RISK_LOG`** — the audit trail. Shaped by `ZCL_ORDER_RISK_ENTITY=>TY_RISK_LOG`. Holds both kinds of rows this project ever writes: one row per check per evaluation (`action = RISK_EVALUATED`, `check_name` filled in) and one row per manual decision (`action = APPROVED`/`REJECTED`, `check_name` blank). Written only by `ZCL_ORDER_RISK_LOGGER->write_log`/`write_action_log`, both `INSERT`-only — nothing in this project ever issues an `UPDATE` against it.
- **`ZORDER_RISK_CONFIG`** — the tunable scoring configuration. Shaped by `ZCL_ORDER_RISK_ENTITY=>TY_RISK_CONFIG`: one row per check name, carrying `max_score`, `threshold_low`, `threshold_high`, and `active`. This is what makes the checker's weights and cutoffs a data problem instead of a code problem.
- **`ZORDER_BLACKLIST`** — customer and/or material restrictions. Shaped by `ZCL_ORDER_RISK_ENTITY=>TY_BLACKLIST`: a `kunnr`/`matnr` pair (either can be blank, meaning "any"), a free-text reason, and an `active` flag, checked by `check_blacklist`.

## 7. A few notes on the ALV dashboard

- `get_log_data` reads the (mocked) log rows, and `build_dashboard_data` immediately collapses them: `LOOP AT ... GROUP BY <ls_log>-vbeln` turns a table with several rows per order (one per check, plus any action rows) into exactly one dashboard row per sales order, summing the check scores back into a single `total_score` inside `LOOP AT GROUP`.
- The `GROUP BY` key is the single field `vbeln`, not a structured key. That's a deliberate simplification for a single-source, in-memory table like this — a structured `GROUP BY` costs more to evaluate for no benefit when there's only one field anyone will ever group by; if the log ever pulled from more than one system and needed to disambiguate order numbers, that would be the moment to make the key structured.
- Approve and Reject never touch the grouped `total_score`/`risk_level` a user is looking at. Each one calls `mo_logger->write_action_log( )`, which inserts a brand-new row into the audit log (keeping the INSERT-only rule from §1 intact), and then updates the on-screen table directly: `ASSIGN mt_alv_data[ ls_row-index ] TO FIELD-SYMBOL(<ls_approve>)` followed by `<ls_approve>-action = ...`, then `mo_grid->refresh_table_display( )`. The audit trail and the screen are updated by two different mechanisms on purpose — the log is the permanent record, the field-symbol assignment is just so the user doesn't have to re-run the selection to see their own click reflected.
- "Show Check Details" doesn't re-query anything — it filters the risk logs already held in `mt_raw_logs` down to the rows for one `vbeln` where `check_name` is filled, and displays them with `CL_SALV_TABLE` in a popup (`set_screen_popup`). `CL_SALV_TABLE` rather than `CL_GUI_ALV_GRID` here specifically because this view needs none of the things `CL_GUI_ALV_GRID` is chosen for elsewhere — no per-row coloring, no custom toolbar — so the simpler API is enough for a one-shot read-only popup.
- Row coloring reuses the same pattern as the rest of this portfolio: `ROW_COLOR` (`CHAR3`) is a field on `ty_dashboard_line`, set in `build_dashboard_data` from `zcl_order_risk_entity=>gc_color` based on the group's risk level, and `build_layout` points `LVC_S_LAYO-INFO_FNAME` at it — the field never appears in the field catalog, so it colors the row without ever being shown as a column.

## 8. What's simplified on purpose

- **Mock data instead of real tables** — every check, plus the config and log reads, uses a `VALUE #( ... )` literal with the real `SELECT`/`INSERT` written as a comment directly above it (see §1). Nothing about *where* the data should come from is left undocumented — only the act of actually connecting to it is deferred.
- **The BAdI is an adapter, not a fixed interface implementation** — `ZCL_IM_ORDER_RISK` deliberately does not implement `IF_EX_...` for any specific BAdI. The class header spells out why: the BAdI (or user exit) that fires on sales order save is not the same one across ECC and different S/4HANA releases, so hardcoding against one interface would make this class work on some systems and fail to even activate on others. Instead it exposes a plain `on_order_save( )` method and documents, in comments, which BAdI to look for and an example adapter method to wire it up — the adapter is the only piece that has to change per system.
- **E-mail recipients are hardcoded** — `resolve_recipient` in `ZCL_ORDER_RISK_NOTIFIER` always returns the same two addresses for HIGH/CRITICAL. The comment above it shows what a real lookup would do: resolve the order's sales group (`VBAK-VKGRP`) to a responsible person via `TVKGR`, then to an e-mail address via `ADR6`, so the alert goes to whoever actually owns that customer instead of a fixed pair of addresses regardless of who's involved.
- **The three Z-tables don't physically exist** — `ZORDER_RISK_LOG`, `ZORDER_RISK_CONFIG`, and `ZORDER_BLACKLIST` are documented shapes (`ty_risk_log`, `ty_risk_config`, `ty_blacklist`) with commented-out `INSERT`/`SELECT` statements standing in for them, the same convention used throughout this portfolio.
- **Single client, no authority checks** — nothing here does an `AUTHORITY-CHECK` before letting a user approve/reject an order or view the dashboard. A real rollout would gate at least the Approve/Reject buttons behind an authorization object tied to the user's sales group or role.

## 9. Possible extensions

- **Real Open SQL access** — replace every mock block with the SELECT/INSERT already sketched in the comment above it; the checker's control flow, the engine, and the dashboard don't need to change at all.
- **ABAP Unit tests for each check and the scoring** — every `check_*` method already takes plain inputs and a config structure and returns a plain `ty_risk_check`, which is exactly the shape a friend test class needs; `calculate_risk_level` is equally easy to hit at each score-band boundary.
- **Move scoring weights fully into an SM30 maintenance view** — `ZCL_ORDER_RISK_CONFIG` already reads a flat table shape; adding a generated maintenance view over `ZORDER_RISK_CONFIG` would let risk owners retune weights and thresholds without a developer in the loop at all.
- **More checks** — delivery block history or dunning level would slot into the checker the same way the existing seven do: one more method, one more config row, one more `WHEN` in the `CASE` inside `evaluate`.
- **Workflow integration for HIGH approvals** — right now HIGH only triggers an e-mail; routing it through SAP Business Workflow instead (or in addition) would give HIGH orders the same kind of trackable approve/reject step CRITICAL orders get manually from the dashboard, instead of relying on someone reading an inbox.

---

# Teknik Mimari — Order Risk Engine

## 1. Neden bu şekilde kurgulandı

Buradaki temel fikir bu portfolyonun geri kalanıyla aynı — her sınıfın tek bir işi var — ama bu projede buna bir kısıtlama daha ekleniyor: bir siparişin gerçekten bloklanıp bloklanmayacağına karar veren yer bir BAdI, ve BAdI'ler iş mantığı koymak için gerçekten zorlu bir yer. İçlerinde adım adım debug yapmak kolay değil, başka birinin transaction'ı içinde çalışıyorlar ve yanlış anda yanlış exception fırlatan bir bug, production'da bir satış siparişinin kaydedilmesini durdurabilir. Bu yüzden tasarım, karar verme işinin tamamını BAdI'nin *dışına*, tek başına inşa edilip çağrılıp test edilebilen düz sınıflara çekiyor.

- **Sorumlulukların ayrılması** — değerlendirme (`ZCL_ORDER_RISK_CHECKER`), bildirim (`ZCL_ORDER_RISK_NOTIFIER`), audit log (`ZCL_ORDER_RISK_LOGGER`), orkestrasyon (`ZCL_ORDER_RISK_ENGINE`), sunum (`ZCL_ORDER_RISK_ALV`) ve BAdI giriş noktası (`ZCL_IM_ORDER_RISK`) tek bir sınıfın altı metodu değil, altı ayrı sınıf. Bir müşterinin ödeme geçmişini puanlamanın e-posta göndermekle ya da bir ALV grid çizmekle hiçbir ilgisi yok, o yüzden her biri sadece yapması gereken tek çağrının ötesinde birbirinden habersiz.
- **Engine bilinçli olarak edilgen** — `ZCL_ORDER_RISK_ENGINE->EVALUATE_ORDER` siparişi puanlıyor, audit log'unu yazıyor, gerekiyorsa uyarı gönderiyor ve bir `ty_risk_result` döndürüyor. Hepsi bu kadar. Hiçbir zaman exception fırlatmıyor, hiçbir şeyi bloklamıyor — sınıfın en üstündeki yorum bunu açıkça söylüyor. Bu bir gözden kaçma değil, tam olarak amacın kendisi: engine, CRITICAL bir sonuçla ne yapılacağına karar vermeye başladığı an, sadece tam o davranışı isteyen tek yerden güvenle çağrılabilir hale gelirdi. Bunun yerine temiz bir "değerlendir ve raporla" servisi olarak kaldığı için, aynı `NEW zcl_order_risk_engine( )->evaluate_order( ... )` çağrısı gece çalışan bir batch job'da dünün siparişlerini puanlarken de, bir müşterinin tüm açık sipariş defterini yeniden kontrol eden bir raporda da, dönen skoru assert eden bir ABAP Unit testinde de, BAdI'nin kendisinde de aynen çalışıyor — ve bu çağıranlardan hiçbiri diğerlerinden birine özgü bir davranışın etrafından dolanmak zorunda kalmıyor.
- **Config'den beslenen puanlama** — `ZCL_ORDER_RISK_CHECKER` içindeki yedi kontrolden hiçbiri bir ağırlığı ya da eşik değerini kod içine gömmüyor. Her biri, `ZCL_ORDER_RISK_CONFIG->GET_CONFIG`'ten gelen (ve `ZORDER_RISK_CONFIG`'i okuması amaçlanan) bir `is_config` yapısı alıyor (`max_score`, `threshold_low`, `threshold_high`, `active`). Kredi riskinin başta düşünülenden daha ağır basması gerektiği ortaya çıkarsa, bu bir tablo bakım değişikliği olur, `ZCL_ORDER_RISK_CHECKER`'ın transport edilmesi değil. `GET_CONFIG`, `active = abap_false` olan her şeyi de eliyor, yani bir kontrol koddaki her şeyden — sadece bir raporda gizlenmekle kalmayıp puanlama döngüsünden de — koda dokunmadan tamamen kapatılabiliyor.
- **Değiştirilebilir veri kaynağı** — bu projedeki her mock veri bloğunun (kredi riski, ödeme gecikmesi, sipariş geçmişi, stok, blacklist, fiyat listeleri, müşteri segmenti, ayrıca config ve log tabloları) hemen üstünde gerçek `SELECT`/`INSERT` yorum satırı olarak duruyor. Örneğin `check_credit_limit`, bugün onların yerini tutan `VALUE #( ... )` literal'inin hemen üstünde yorum olarak `SELECT SINGLE klimk FROM knkk` ve `SELECT SUM( dmbtr ) FROM bsid` satırlarını içeriyor. Canlıya geçmek, bu birkaç noktanın her birinde mock bloğunu silip SELECT'in yorumunu kaldırmaktan ibaret — checker'ın akışında, config sınıfında ya da engine'de hiçbir şey değişmiyor.
- **Bilinçli olarak tasarlanmış audit** — `ZCL_ORDER_RISK_LOGGER`'ın tam olarak iki public metodu var: `write_log` (her değerlendirmede kontrol başına bir satır) ve `write_action_log` (her manuel Approve/Reject tıklamasında bir satır) — ve ikisi de sadece `INSERT` yapıyor. Bir `update_log` metodu yok ve bu kod tabanında hiçbir yer bir `ZORDER_RISK_LOG` satırını yeniden yazmıyor. Bu bilinçli: sonradan düzenlenebilen bir audit trail, gerçekte audit trail değildir. CRITICAL bir sipariş daha sonra bir yönetici tarafından onaylanırsa, bu onay değerlendirme satırlarının üzerine *yeni* bir satır olarak ekleniyor, onları düzelten bir güncelleme değil — dashboard bunları sipariş bazında tekrar bir araya getiriyor (bkz. §7), ama alttaki log her zaman hem engine'in bulduğunu hem de bir insanın buna karşı ne yaptığını gösteriyor.

## 2. Kim ne yapıyor

| Sınıf | Katman | Sorumluluk |
|---|---|---|
| `ZCL_ORDER_RISK_ENTITY` | Domain types | Ortak yapılar ve sabitler (`ty_order_item`, `ty_risk_check`, `ty_risk_result`, `ty_risk_config`, `ty_risk_log`, `ty_blacklist`, ayrıca risk seviyesi, renk, skor eşiği, aksiyon ve kontrol adı sabitleri). Hiçbir zaman instantiate edilmiyor — `CREATE PRIVATE`. |
| `ZCL_ORDER_RISK_CONFIG` | Konfigürasyon | `ZORDER_RISK_CONFIG`'te tutulması amaçlanan puanlama konfigürasyonunu (kontrol başına ağırlık ve eşikler) okuyor. |
| `ZCL_ORDER_RISK_CHECKER` | Domain mantığı | Bir siparişe karşı yedi ağırlıklı risk kontrolünü çalıştırıyor, skorlarını topluyor ve toplamı bir risk seviyesine eşliyor. |
| `ZCL_ORDER_RISK_NOTIFIER` | Bildirim | Risk uyarı e-postasını gönderiyor, ama sadece HIGH ve CRITICAL sonuçlar için. |
| `ZCL_ORDER_RISK_LOGGER` | Audit | Audit trail'i yazıyor — her değerlendirmede kontrol başına bir satır, artı her manuel onay/red aksiyonu için bir satır. |
| `ZCL_ORDER_RISK_ENGINE` | Orkestrasyon | checker → logger → notifier sırasıyla çağırıyor ve sonucu döndürüyor. Hiçbir zaman exception fırlatmıyor, hiçbir şeyi bloklamıyor. |
| `ZCL_IM_ORDER_RISK` | BAdI giriş noktası | Bir risk seviyesini kaydı bloklayan bir karara çeviren tek yer. |
| `ZCL_ORDER_RISK_ALV` | Sunum | Dashboard: audit log'u okuyor, satış siparişi bazında gruplayıp renk kodlu bir ALV grid'i olarak, Approve/Reject/Details/Export aksiyonlarıyla birlikte gösteriyor. |
| `ZORDER_RISK_MONITOR` | Giriş noktası | Çalıştırılabilir rapor: seçim ekranı (tarih aralığı, risk seviyesi, müşteri), screen 100 akışı, ALV sınıfını instantiate ediyor. |

## 3. Bir istek sistemin içinden nasıl geçiyor

**BAdI tarafı — VA01'de bir sipariş kaydediliyor:**

```
VA01 kaydet
    │
    ▼
BAdI adaptörü (SD_SALES_DOCUMENT_SAVE / BADI_SD_SALES_ITEM / user exit — bu adımın neden
bilinçli olarak sabit tutulmadığı için §5'e ve ZCL_IM_ORDER_RISK'in sınıf başlığına bakın)
    │  VBAK/VBAP'ı ty_order_items'a eşliyor
    ▼
ZCL_IM_ORDER_RISK->on_order_save( iv_vbeln, iv_kunnr, it_items )
    │
    ▼
ZCL_ORDER_RISK_ENGINE->evaluate_order( )
    │
    ├─► ZCL_ORDER_RISK_CHECKER->evaluate( )
    │         ├─ check_credit_limit()      ~ KNKK + BSID
    │         ├─ check_payment_perf()      ~ BSID/BSAD ortalama gecikme günü
    │         ├─ check_order_anomaly()     ~ VBAK/VBAP 3 aylık ortalama
    │         ├─ check_stock()             ~ MARD kullanılabilir stok
    │         ├─ check_blacklist()         ~ ZORDER_BLACKLIST
    │         ├─ check_price_deviation()   ~ VBAP/KONV liste fiyatı
    │         ├─ check_customer_segment()  ~ KNVV
    │         └─ calculate_risk_level()    → total_score, risk_level
    │
    ├─► ZCL_ORDER_RISK_LOGGER->write_log( )      → kontrol başına bir audit satırı
    │
    └─► ZCL_ORDER_RISK_NOTIFIER->send_risk_alert( )   → e-posta, sadece HIGH/CRITICAL ise
    │
    ▼  (sonuç BAdI'ye dönüyor)
ZCL_IM_ORDER_RISK
    │
    ▼
CASE ls_result-risk_level.
    LOW      → aksiyon yok, sipariş sessizce kaydediliyor
    MEDIUM   → MESSAGE TYPE 'S' DISPLAY LIKE 'W' (bilgilendirme amaçlı)
    HIGH     → MESSAGE TYPE 'S' DISPLAY LIKE 'W' (bilgilendirme, yönetici zaten e-postayla bilgilendirildi)
    CRITICAL → MESSAGE TYPE 'E'  →  kayıt bloklanıyor
```

**Dashboard tarafı — biri geçmiş değerlendirmeleri incelemek için monitörü açıyor:**

```
ZORDER_RISK_MONITOR (seçim ekranı: tarih aralığı / risk seviyesi / müşteri)
    │
    ▼
CALL SCREEN 100
    │
    ▼
ZCL_ORDER_RISK_ALV->display( iv_date_from, iv_date_to, iv_risk_level, iv_kunnr )
    │
    ├─ get_log_data()          ~ SELECT * FROM ZORDER_RISK_LOG WHERE ...
    ├─ build_dashboard_data()  → GROUP BY vbeln, sipariş başına bir satır (kontrol başına değil)
    ├─ build_fieldcatalog() / build_layout()   → ROW_COLOR ile renklendirme
    └─ CL_GUI_ALV_GRID->set_table_for_first_display()

Kullanıcı bir satır seçip toolbar'dan bir butona basıyor
    │
    ▼
on_user_command( e_ucomm )
    ├─ APPROVE       → write_action_log( ..., gc_action-approved )  → satır yerinde güncelleniyor
    ├─ REJECT        → write_action_log( ..., gc_action-rejected )  → satır yerinde güncelleniyor
    ├─ SHOW_DETAILS  → show_check_details( vbeln )  → CL_SALV_TABLE popup'ı, kontrol bazlı döküm
    └─ EXCEL_EXPORT  → export_to_excel( )  → mt_alv_data'nın tab ile ayrılmış dosya indirmesi
```

## 4. Yedi kontrol ve puanlama

| Kontrol | Neye bakıyor (gerçek tablolar) | Maks. skor | Mantık |
|---|---|---|---|
| `CREDIT_LIMIT` | `KNKK` kredi limiti + `BSID` açık kalemler | 25 | Kullanım = (açık bakiye + bu sipariş) / kredi limiti. ≥%100 → tam skor; ≥%90 → %70; ≥%80 → %40; altında → 0. |
| `PAYMENT_PERF` | `BSID`/`BSAD` ortalama gecikme günü | 20 | `threshold_high`'ın üstü → tam skor; `threshold_low` ile `threshold_high` arası → doğrusal artış; `threshold_low`'un altı → 0. |
| `ORDER_ANOMALY` | `VBAK`/`VBAP` 3 aylık ortalama sipariş değeri | 15 | Sipariş değeri o müşterinin ortalamasına kıyasla. Ortalamanın %200'ünden fazla → tam skor; ≥%100+`threshold_high` → %60; ≥%100+`threshold_low` → %30; aksi halde 0. |
| `STOCK` | `MARD` kullanılabilir stok vs. sipariş miktarı | 15 | Yetersiz stoklu sipariş kalemi yüzdesi. %100 eksik → tam skor; `threshold_high`'ın üstü → %60; `threshold_low`'un üstü → %30; aksi halde 0. |
| `BLACKLIST` | `ZORDER_BLACKLIST` (müşteri ve/veya malzeme kısıtlaması) | 25 | İkili — müşteri, malzeme ya da kombinasyonda aktif bir eşleşme → tam skor; aksi halde 0. |
| `PRICE_DEV` | Sipariş fiyatı vs. liste fiyatı (`VBAP`/`KONV`) | 10 | İndirim yüzdesi `threshold_high`'ın üstünde → tam skor; `threshold_low`'un üstünde → %50; aksi halde 0. |
| `CUSTOMER_SEG` | Müşteri segmenti (`KNVV`'den türetilmesi amaçlanan) | 10 | Segment C → tam skor; segment B → %50; segment A → 0. |

Yedi skor toplanarak `total_score`'u oluşturuyor, bu sayı da `ZCL_ORDER_RISK_ENTITY` içindeki `gc_score_threshold` ile bir risk seviyesine eşleniyor:

| Skor | Risk seviyesi |
|---|---|
| 0 – 30 | LOW |
| 31 – 60 | MEDIUM |
| 61 – 85 | HIGH |
| 86+ | CRITICAL |

Hem kontrol başına ağırlıklar hem de skor-seviye kesim noktaları, `ZCL_ORDER_RISK_CHECKER`'ın içine gömülü sayılar değil, konfigürasyondan geliyor: ağırlıklar (`max_score`, `threshold_low`, `threshold_high`) `ZCL_ORDER_RISK_CONFIG`'ten, dört skor bandı da `zcl_order_risk_entity=>gc_score_threshold`'tan geliyor. Engine'in bütününün ne kadar hassas çalıştığını yeniden ayarlamak — mesela 61'in HIGH için fazla agresif bir eşik olduğuna karar vermek — puanlama döngüsünü yeniden yazmak değil, bir sabiti ya da bir config tablosu satırını değiştirmek demek.

## 5. Bloklama kararı — neden engine'de değil de BAdI'de yaşıyor

`ZCL_ORDER_RISK_ENGINE->evaluate_order`, bir `ty_risk_result` döndürüp orada duruyor. `risk_level` üzerinde `CASE`'i çalıştıran ve sadece CRITICAL için `MESSAGE ... TYPE 'E'` çalıştıran yer `ZCL_IM_ORDER_RISK->on_order_save`. Bu, tüm kod tabanında bir kaydı gerçekten durduran tek satır — bir BAdI içinden fırlatılan `MESSAGE TYPE 'E'`, klasik bir doğrulama hatasının yapacağı gibi çevredeki update'i iptal ediyor.

`RAISE`/`MESSAGE TYPE 'E'`'nin bilinçli olarak engine'in dışında tutulmasının sebebi, "kaydı blokla"nın sadece bir BAdI içinde anlamlı olan bir şey olması. Geçen ayın siparişlerini yeniden puanlayan bir batch job, CRITICAL bir sonucun job'ı öldürecek bir exception fırlatmasını istemez — bir rapor yazabilmek için sonucu geri istiyor. `total_score = 86` diye assert eden bir unit test, test ettiği sayıya ulaşmak için bir exception yakalamak istemiyor. VA01'in içinde bile, bloklamak aslında bir *politika* kararı ("CRITICAL siparişleri mi durduruyoruz, yoksa HIGH-ve-üstünü mü, yoksa hiçbirini mi") ve bu, diğer her çağıranın da bağımlı olduğu sınıfı değiştirmekten çok, küçük bir `CASE` ifadesinde değiştirmek daha doğal. Engine'i pasif bir raportör olarak tutup, sonuç doğuran tek `MESSAGE TYPE 'E'`'yi onun üzerine oturan en ince katmana koymak, diğer tüm tüketicilerin engine'i güvenle çağrılabilir bir şey olarak görebilmesini sağlayan şey.

## 6. Üç Z-tablosu

- **`ZORDER_RISK_LOG`** — audit trail. `ZCL_ORDER_RISK_ENTITY=>TY_RISK_LOG` ile şekillendirilmiş. Bu projenin yazdığı iki tür satırı da barındırıyor: değerlendirme başına kontrol başına bir satır (`action = RISK_EVALUATED`, `check_name` dolu) ve manuel karar başına bir satır (`action = APPROVED`/`REJECTED`, `check_name` boş). Sadece `ZCL_ORDER_RISK_LOGGER->write_log`/`write_action_log` tarafından yazılıyor, ikisi de sadece `INSERT` — bu projede ona karşı hiçbir `UPDATE` çalıştırılmıyor.
- **`ZORDER_RISK_CONFIG`** — ayarlanabilir puanlama konfigürasyonu. `ZCL_ORDER_RISK_ENTITY=>TY_RISK_CONFIG` ile şekillendirilmiş: kontrol adı başına bir satır, `max_score`, `threshold_low`, `threshold_high` ve `active`'i taşıyor. Checker'ın ağırlıklarını ve kesim noktalarını bir kod problemi yerine bir veri problemi haline getiren şey bu.
- **`ZORDER_BLACKLIST`** — müşteri ve/veya malzeme kısıtlamaları. `ZCL_ORDER_RISK_ENTITY=>TY_BLACKLIST` ile şekillendirilmiş: bir `kunnr`/`matnr` çifti (ikisinden biri boş olabilir, "herhangi biri" anlamına gelir), serbest metin bir gerekçe ve `check_blacklist` tarafından kontrol edilen bir `active` bayrağı.

## 7. ALV dashboard hakkında birkaç not

- `get_log_data` (mock) log satırlarını okuyor, `build_dashboard_data` da bunları hemen topluyor: `LOOP AT ... GROUP BY <ls_log>-vbeln`, sipariş başına birden fazla satır içeren bir tabloyu (kontrol başına bir satır, artı varsa aksiyon satırları) `LOOP AT GROUP` içinde kontrol skorlarını tek bir `total_score`'da toplayarak tam olarak sipariş başına bir dashboard satırına indiriyor.
- `GROUP BY` anahtarı tek bir alan, `vbeln` — yapılandırılmış bir anahtar değil. Bu, bu projedeki gibi tek kaynaklı, bellek-içi bir tablo için bilinçli bir basitleştirme: kimsenin gruplayacağı tek bir alan varken yapılandırılmış bir `GROUP BY`'ın maliyeti hiçbir fayda karşılığı olmadan artar; log ileride birden fazla sistemden besleniyor olsaydı ve sipariş numaralarını ayırt etmek gerekseydi, anahtarı yapılandırılmış hale getirmenin tam zamanı orası olurdu.
- Approve ve Reject, kullanıcının baktığı gruplanmış `total_score`/`risk_level`'a hiç dokunmuyor. Her ikisi de `mo_logger->write_action_log( )`'i çağırıyor, bu da audit log'a yepyeni bir satır ekliyor (§1'deki sadece-INSERT kuralını koruyarak), sonra ekrandaki tabloyu doğrudan güncelliyor: `ASSIGN mt_alv_data[ ls_row-index ] TO FIELD-SYMBOL(<ls_approve>)`'ın ardından `<ls_approve>-action = ...`, sonra `mo_grid->refresh_table_display( )`. Audit trail ve ekran bilinçli olarak iki farklı mekanizmayla güncelleniyor — log kalıcı kayıt, field-symbol ataması ise sadece kullanıcının kendi tıklamasını görmek için seçim ekranını yeniden çalıştırmak zorunda kalmaması için.
- "Show Check Details" hiçbir şeyi yeniden sorgulamıyor — zaten bellekte tutulan `mt_raw_logs`'u tek bir `vbeln` için `check_name` dolu olan satırlara filtreleyip `CL_SALV_TABLE` ile bir popup'ta gösteriyor (`set_screen_popup`). Burada `CL_GUI_ALV_GRID` yerine özellikle `CL_SALV_TABLE` kullanılıyor çünkü bu görünüm, `CL_GUI_ALV_GRID`'in başka yerlerde seçilme sebebi olan hiçbir şeye ihtiyaç duymuyor — satır bazlı renklendirme yok, özel toolbar yok — yani tek seferlik, salt okunur bir popup için daha basit API yeterli.
- Satır renklendirmesi bu portfolyonun geri kalanıyla aynı deseni tekrarlıyor: `ROW_COLOR` (`CHAR3`), `ty_dashboard_line`'ın bir alanı, `build_dashboard_data` içinde grubun risk seviyesine göre `zcl_order_risk_entity=>gc_color`'dan set ediliyor, `build_layout` da `LVC_S_LAYO-INFO_FNAME`'i buna işaret ettiriyor — alan hiçbir zaman field catalog'a girmiyor, yani grid bunu bir sütun olarak hiç göstermeden satırı renklendirmek için kullanıyor.

## 8. Bilinçli olarak basitleştirilenler

- **Gerçek tablolar yerine mock veri** — her kontrol, ayrıca config ve log okumaları, hemen üstünde gerçek `SELECT`/`INSERT`'in yorum satırı olarak durduğu bir `VALUE #( ... )` literal'i kullanıyor (bkz. §1). Verinin *nereden* gelmesi gerektiği konusunda belgelenmemiş hiçbir şey yok — sadece ona gerçekten bağlanma eylemi erteleniyor.
- **BAdI, sabit bir interface implementasyonu değil, bir adaptör** — `ZCL_IM_ORDER_RISK` bilinçli olarak belirli bir BAdI için `IF_EX_...` implemente etmiyor. Sınıfın başlığı nedenini açıkça anlatıyor: satış siparişi kaydında tetiklenen BAdI (ya da user exit), ECC ile farklı S/4HANA sürümleri arasında aynı değil, yani tek bir interface'e karşı sabit kodlamak bu sınıfı bazı sistemlerde çalışır, bazılarında aktive bile edilemez hale getirirdi. Bunun yerine düz bir `on_order_save( )` metodu sunuyor ve yorum satırlarında hangi BAdI'nin aranacağını ve bunu bağlamak için örnek bir adaptör metodunu belgeliyor — sisteme göre değişmesi gereken tek parça adaptör.
- **E-posta alıcıları sabit kodlanmış** — `ZCL_ORDER_RISK_NOTIFIER` içindeki `resolve_recipient`, HIGH/CRITICAL için her zaman aynı iki adresi döndürüyor. Üstündeki yorum, gerçek bir lookup'ın ne yapacağını gösteriyor: siparişin satış grubunu (`VBAK-VKGRP`) `TVKGR` üzerinden sorumlu kişiye, sonra `ADR6` üzerinden bir e-posta adresine çözmek — böylece uyarı, kimin dahil olduğuna bakılmaksızın sabit bir adres çiftine değil, o müşteriye gerçekten sahip olan kişiye gidiyor.
- **Üç Z-tablosu fiziksel olarak mevcut değil** — `ZORDER_RISK_LOG`, `ZORDER_RISK_CONFIG` ve `ZORDER_BLACKLIST`, bu portfolyonun her yerinde geçerli olan aynı kuralla, onların yerini tutan yorum satırı haline getirilmiş `INSERT`/`SELECT` ifadeleriyle birlikte belgelenmiş yapılar (`ty_risk_log`, `ty_risk_config`, `ty_blacklist`).
- **Tek client, authority check yok** — burada bir kullanıcının bir siparişi onaylamasına/reddetmesine ya da dashboard'u görüntülemesine izin vermeden önce hiçbir yerde `AUTHORITY-CHECK` çalışmıyor. Gerçek bir devreye alım en azından Approve/Reject butonlarını, kullanıcının satış grubuna ya da rolüne bağlı bir yetki objesinin arkasına koyardı.

## 9. Olası genişletmeler

- **Gerçek Open SQL erişimi** — her mock bloğu, hemen üstünde zaten taslağı çıkarılmış SELECT/INSERT ile değiştirmek; checker'ın akışı, engine ve dashboard hiç değişmeden kalıyor.
- **Her kontrol ve puanlama için ABAP Unit testleri** — her `check_*` metodu zaten düz girdiler ve bir config yapısı alıp düz bir `ty_risk_check` döndürüyor, ki bu tam olarak friend bir test sınıfının ihtiyaç duyduğu şekil; `calculate_risk_level`'ı her skor bandı sınırında test etmek de aynı derecede kolay.
- **Puanlama ağırlıklarını tamamen bir SM30 bakım görünümüne taşımak** — `ZCL_ORDER_RISK_CONFIG` zaten düz bir tablo şeklini okuyor; `ZORDER_RISK_CONFIG` üzerine generate edilmiş bir bakım görünümü eklemek, risk sahiplerinin ağırlıkları ve eşikleri hiç bir geliştirici olmadan yeniden ayarlayabilmesini sağlardı.
- **Daha fazla kontrol** — teslimat blok geçmişi ya da ihtar (dunning) seviyesi, mevcut yedi kontrolün yaptığı gibi checker'a eklenebilirdi: bir metod daha, bir config satırı daha, `evaluate` içindeki `CASE`'e bir `WHEN` daha.
- **HIGH onayları için workflow entegrasyonu** — şu an HIGH sadece bir e-posta tetikliyor; bunu (ya da buna ek olarak) SAP Business Workflow üzerinden yönlendirmek, HIGH siparişlere de CRITICAL siparişlerin dashboard'dan manuel olarak aldığı türden izlenebilir bir onay/red adımı kazandırırdı — birinin gelen kutusunu okumasına güvenmek yerine.
