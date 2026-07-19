*&---------------------------------------------------------------------*
*& Class ZCL_ORDER_RISK_CHECKER
*&---------------------------------------------------------------------*
CLASS zcl_order_risk_checker DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS:
      constructor,

      evaluate
        IMPORTING iv_vbeln      TYPE vbeln
                  iv_kunnr      TYPE kunnr
                  it_items      TYPE zcl_order_risk_entity=>ty_order_items
        RETURNING VALUE(rs_result) TYPE zcl_order_risk_entity=>ty_risk_result.

  PRIVATE SECTION.

    DATA mo_config TYPE REF TO zcl_order_risk_config.

    METHODS:
      check_credit_limit
        IMPORTING iv_kunnr  TYPE kunnr
                  it_items  TYPE zcl_order_risk_entity=>ty_order_items
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      check_payment_perf
        IMPORTING iv_kunnr  TYPE kunnr
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      check_order_anomaly
        IMPORTING iv_kunnr  TYPE kunnr
                  it_items  TYPE zcl_order_risk_entity=>ty_order_items
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      check_stock
        IMPORTING it_items  TYPE zcl_order_risk_entity=>ty_order_items
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      check_blacklist
        IMPORTING iv_kunnr  TYPE kunnr
                  it_items  TYPE zcl_order_risk_entity=>ty_order_items
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      check_price_deviation
        IMPORTING it_items  TYPE zcl_order_risk_entity=>ty_order_items
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      check_customer_segment
        IMPORTING iv_kunnr  TYPE kunnr
                  is_config TYPE zcl_order_risk_entity=>ty_risk_config
        RETURNING VALUE(rs_check) TYPE zcl_order_risk_entity=>ty_risk_check,

      calculate_risk_level
        IMPORTING iv_total_score TYPE i
        RETURNING VALUE(rv_level) TYPE char10.

ENDCLASS.


CLASS zcl_order_risk_checker IMPLEMENTATION.

  METHOD constructor.

    mo_config = NEW zcl_order_risk_config( ).

  ENDMETHOD.

  METHOD evaluate.

    DATA(lt_config) = mo_config->get_config( ).

    rs_result-vbeln = iv_vbeln.
    rs_result-kunnr = iv_kunnr.

    LOOP AT lt_config ASSIGNING FIELD-SYMBOL(<ls_config>).
      CASE <ls_config>-check_name.
        WHEN zcl_order_risk_entity=>gc_check-credit_limit.
          APPEND check_credit_limit( iv_kunnr  = iv_kunnr
                                      it_items  = it_items
                                      is_config = <ls_config> ) TO rs_result-checks.

        WHEN zcl_order_risk_entity=>gc_check-payment_perf.
          APPEND check_payment_perf( iv_kunnr  = iv_kunnr
                                      is_config = <ls_config> ) TO rs_result-checks.

        WHEN zcl_order_risk_entity=>gc_check-order_anomaly.
          APPEND check_order_anomaly( iv_kunnr  = iv_kunnr
                                       it_items  = it_items
                                       is_config = <ls_config> ) TO rs_result-checks.

        WHEN zcl_order_risk_entity=>gc_check-stock.
          APPEND check_stock( it_items  = it_items
                               is_config = <ls_config> ) TO rs_result-checks.

        WHEN zcl_order_risk_entity=>gc_check-blacklist.
          APPEND check_blacklist( iv_kunnr  = iv_kunnr
                                   it_items  = it_items
                                   is_config = <ls_config> ) TO rs_result-checks.

        WHEN zcl_order_risk_entity=>gc_check-price_dev.
          APPEND check_price_deviation( it_items  = it_items
                                         is_config = <ls_config> ) TO rs_result-checks.

        WHEN zcl_order_risk_entity=>gc_check-customer_seg.
          APPEND check_customer_segment( iv_kunnr  = iv_kunnr
                                          is_config = <ls_config> ) TO rs_result-checks.
      ENDCASE.
    ENDLOOP.

    DATA(lv_total_score) = 0.
    LOOP AT rs_result-checks ASSIGNING FIELD-SYMBOL(<ls_check>).
      lv_total_score = lv_total_score + <ls_check>-score.
    ENDLOOP.
    rs_result-total_score = lv_total_score.

    rs_result-risk_level = calculate_risk_level( rs_result-total_score ).

  ENDMETHOD.

  METHOD check_credit_limit.

    TYPES:
      BEGIN OF ty_credit_mock,
        kunnr        TYPE kunnr,
        credit_limit TYPE netwr,
        open_balance TYPE netwr,
      END OF ty_credit_mock,
      ty_credit_mock_tab TYPE STANDARD TABLE OF ty_credit_mock WITH EMPTY KEY.

    " S/4HANA (SAP Credit Management / FSCM):
    " SELECT SINGLE credit_limit FROM ukmbp_cms_sgm INTO @DATA(lv_credit_limit)
    "   WHERE partner = @iv_kunnr AND credit_sgmnt = @lv_credit_segment.
    " SELECT SUM( dmbtr ) FROM bsid INTO @DATA(lv_open_balance) WHERE kunnr = @iv_kunnr.
    "
    " Classic ECC used KNKK-KLIMK for the credit limit; that table is no longer
    " populated in S/4HANA, so FSCM is the correct source there.

    DATA(lt_credit_mock) = VALUE ty_credit_mock_tab(
      ( kunnr = '0000100000' credit_limit = '50000.00' open_balance = '10000.00' )
      ( kunnr = '0000100001' credit_limit = '20000.00' open_balance = '15000.00' )
      ( kunnr = '0000100002' credit_limit = '10000.00' open_balance = '9500.00' )
    ).

    READ TABLE lt_credit_mock INTO DATA(ls_credit) WITH KEY kunnr = iv_kunnr.
    IF sy-subrc <> 0.
      ls_credit-credit_limit = '30000.00'.
      ls_credit-open_balance = '5000.00'.
    ENDIF.

    DATA(lv_order_value) = CONV netwr( 0 ).
    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      IF <ls_item>-kpein IS NOT INITIAL.
        lv_order_value = lv_order_value + <ls_item>-menge * <ls_item>-netpr / <ls_item>-kpein.
      ELSE.
        lv_order_value = lv_order_value + <ls_item>-menge * <ls_item>-netpr.
      ENDIF.
    ENDLOOP.

    DATA(lv_usage_pct) = ( ls_credit-open_balance + lv_order_value ) / ls_credit-credit_limit * 100.
    DATA(lv_pct_display) = round( val = lv_usage_pct dec = 0 ).

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.

    IF lv_usage_pct >= 100.
      rs_check-score  = is_config-max_score.
      rs_check-passed = abap_false.
    ELSEIF lv_usage_pct >= 90.
      rs_check-score  = is_config-max_score * 70 / 100.
      rs_check-passed = abap_true.
    ELSEIF lv_usage_pct >= 80.
      rs_check-score  = is_config-max_score * 40 / 100.
      rs_check-passed = abap_true.
    ELSE.
      rs_check-score  = 0.
      rs_check-passed = abap_true.
    ENDIF.

    rs_check-message = |Credit usage at { lv_pct_display }% of limit|.

  ENDMETHOD.

  METHOD check_payment_perf.

    TYPES:
      BEGIN OF ty_delay_mock,
        kunnr TYPE kunnr,
        days  TYPE i,
      END OF ty_delay_mock,
      ty_delay_mock_tab TYPE STANDARD TABLE OF ty_delay_mock WITH EMPTY KEY.

    " SELECT FROM bsid/bsad and compute average( ( clearing_date - due_date ) )
    "   grouped by kunnr into an internal table of average delay days.

    DATA(lt_delay_mock) = VALUE ty_delay_mock_tab(
      ( kunnr = '0000100000' days = 2 )
      ( kunnr = '0000100001' days = 10 )
      ( kunnr = '0000100002' days = 25 )
    ).

    READ TABLE lt_delay_mock INTO DATA(ls_delay) WITH KEY kunnr = iv_kunnr.
    IF sy-subrc <> 0.
      ls_delay-days = 5.
    ENDIF.

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.

    IF ls_delay-days > is_config-threshold_high.
      rs_check-score  = is_config-max_score.
      rs_check-passed = abap_false.
    ELSEIF ls_delay-days >= is_config-threshold_low.
      rs_check-score  = round( val = is_config-max_score
                                      * ( ls_delay-days - is_config-threshold_low )
                                      / ( is_config-threshold_high - is_config-threshold_low )
                                dec = 0 ).
      rs_check-passed = abap_true.
    ELSE.
      rs_check-score  = 0.
      rs_check-passed = abap_true.
    ENDIF.

    rs_check-message = |Avg payment delay: { ls_delay-days } days|.

  ENDMETHOD.

  METHOD check_order_anomaly.

    TYPES:
      BEGIN OF ty_avg_mock,
        kunnr     TYPE kunnr,
        avg_value TYPE netwr,
      END OF ty_avg_mock,
      ty_avg_mock_tab TYPE STANDARD TABLE OF ty_avg_mock WITH EMPTY KEY.

    " SELECT AVG( netwr ) FROM vbak AS a INNER JOIN vbap AS b ON a~vbeln = b~vbeln
    "   WHERE a~kunnr = @iv_kunnr AND a~erdat >= @lv_3_months_ago INTO @DATA(lv_avg_value).

    DATA(lt_avg_mock) = VALUE ty_avg_mock_tab(
      ( kunnr = '0000100000' avg_value = '5000.00' )
      ( kunnr = '0000100001' avg_value = '8000.00' )
      ( kunnr = '0000100002' avg_value = '3000.00' )
    ).

    READ TABLE lt_avg_mock INTO DATA(ls_avg) WITH KEY kunnr = iv_kunnr.
    IF sy-subrc <> 0.
      ls_avg-avg_value = '5000.00'.
    ENDIF.

    DATA(lv_order_value) = CONV netwr( 0 ).
    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      IF <ls_item>-kpein IS NOT INITIAL.
        lv_order_value = lv_order_value + <ls_item>-menge * <ls_item>-netpr / <ls_item>-kpein.
      ELSE.
        lv_order_value = lv_order_value + <ls_item>-menge * <ls_item>-netpr.
      ENDIF.
    ENDLOOP.

    DATA(lv_ratio_pct) = COND netwr( WHEN ls_avg-avg_value IS NOT INITIAL
                                        THEN lv_order_value / ls_avg-avg_value * 100
                                        ELSE 100 ).
    DATA(lv_pct_display) = round( val = lv_ratio_pct dec = 0 ).

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.

    IF lv_ratio_pct > 200.
      rs_check-score  = is_config-max_score.
      rs_check-passed = abap_false.
    ELSEIF lv_ratio_pct >= 100 + is_config-threshold_high.
      rs_check-score  = is_config-max_score * 60 / 100.
      rs_check-passed = abap_true.
    ELSEIF lv_ratio_pct >= 100 + is_config-threshold_low.
      rs_check-score  = is_config-max_score * 30 / 100.
      rs_check-passed = abap_true.
    ELSE.
      rs_check-score  = 0.
      rs_check-passed = abap_true.
    ENDIF.

    rs_check-message = |Order { lv_pct_display }% of 3-month average|.

  ENDMETHOD.

  METHOD check_stock.

    TYPES:
      BEGIN OF ty_stock_mock,
        matnr TYPE matnr,
        labst TYPE labst,
      END OF ty_stock_mock,
      ty_stock_mock_tab TYPE STANDARD TABLE OF ty_stock_mock WITH EMPTY KEY.

    " SELECT matnr, labst FROM mard WHERE werks = @<ls_item>-werks
    "   INTO TABLE @DATA(lt_stock) FOR ALL ENTRIES IN @it_items.

    DATA(lt_stock_mock) = VALUE ty_stock_mock_tab(
      ( matnr = 'MAT100010' labst = '100.000' )
      ( matnr = 'MAT100020' labst = '5.000' )
      ( matnr = 'MAT100030' labst = '0.000' )
    ).

    DATA(lv_insufficient) = 0.
    DATA(lv_total_items)  = 0.

    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      lv_total_items = lv_total_items + 1.

      READ TABLE lt_stock_mock INTO DATA(ls_stock) WITH KEY matnr = <ls_item>-matnr.
      IF sy-subrc <> 0.
        ls_stock-labst = '9999.000'.
      ENDIF.

      IF <ls_item>-menge > ls_stock-labst.
        lv_insufficient = lv_insufficient + 1.
      ENDIF.
    ENDLOOP.

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.

    IF lv_total_items = 0.
      rs_check-score  = 0.
      rs_check-passed = abap_true.
    ELSE.
      DATA(lv_shortage_pct) = lv_insufficient * 100 / lv_total_items.

      IF lv_shortage_pct >= 100.
        rs_check-score  = is_config-max_score.
        rs_check-passed = abap_false.
      ELSEIF lv_shortage_pct >= is_config-threshold_high.
        rs_check-score  = is_config-max_score * 60 / 100.
        rs_check-passed = abap_true.
      ELSEIF lv_shortage_pct >= is_config-threshold_low.
        rs_check-score  = is_config-max_score * 30 / 100.
        rs_check-passed = abap_true.
      ELSE.
        rs_check-score  = 0.
        rs_check-passed = abap_true.
      ENDIF.
    ENDIF.

    rs_check-message = |Insufficient stock for { lv_insufficient } of { lv_total_items } items|.

  ENDMETHOD.

  METHOD check_blacklist.

    " SELECT kunnr, matnr, reason, active FROM zorder_blacklist
    "   WHERE active = @abap_true INTO TABLE @DATA(lt_blacklist).

    DATA(lt_blacklist) = VALUE zcl_order_risk_entity=>ty_blacklist_tab(
      ( kunnr = '0000100002' matnr = ''           reason = 'Customer under investigation' active = abap_true )
      ( kunnr = ''           matnr = 'MAT100030'  reason = 'Restricted material'           active = abap_true )
    ).

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.
    rs_check-score      = 0.
    rs_check-passed     = abap_true.
    rs_check-message    = 'No blacklist match'.

    LOOP AT lt_blacklist ASSIGNING FIELD-SYMBOL(<ls_blacklist>) WHERE active = abap_true.
      IF <ls_blacklist>-kunnr IS NOT INITIAL AND <ls_blacklist>-matnr IS INITIAL
         AND <ls_blacklist>-kunnr = iv_kunnr.
        rs_check-score   = is_config-max_score.
        rs_check-passed  = abap_false.
        rs_check-message = 'Customer/material combination is restricted'.
        EXIT.
      ENDIF.

      READ TABLE it_items TRANSPORTING NO FIELDS WITH KEY matnr = <ls_blacklist>-matnr.
      IF sy-subrc = 0
         AND ( <ls_blacklist>-kunnr IS INITIAL OR <ls_blacklist>-kunnr = iv_kunnr ).
        rs_check-score   = is_config-max_score.
        rs_check-passed  = abap_false.
        rs_check-message = 'Customer/material combination is restricted'.
        EXIT.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD check_price_deviation.

    TYPES:
      BEGIN OF ty_price_mock,
        matnr      TYPE matnr,
        list_price TYPE netpr,
      END OF ty_price_mock,
      ty_price_mock_tab TYPE STANDARD TABLE OF ty_price_mock WITH EMPTY KEY.

    " SELECT a~matnr, b~kbetr AS list_price FROM vbap AS a INNER JOIN konv AS b
    "   ON b~knumv = a~knumv AND b~kposn = a~kposn WHERE b~kschl = 'PR00'
    "   INTO TABLE @DATA(lt_list_price).

    DATA(lt_price_mock) = VALUE ty_price_mock_tab(
      ( matnr = 'MAT100010' list_price = '100.00' )
      ( matnr = 'MAT100020' list_price = '50.00' )
      ( matnr = 'MAT100030' list_price = '200.00' )
    ).

    DATA(lv_max_discount_pct) = CONV netpr( 0 ).

    LOOP AT it_items ASSIGNING FIELD-SYMBOL(<ls_item>).
      READ TABLE lt_price_mock INTO DATA(ls_price) WITH KEY matnr = <ls_item>-matnr.
      IF sy-subrc <> 0 OR ls_price-list_price IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_discount_pct) = ( ls_price-list_price - <ls_item>-netpr ) * 100 / ls_price-list_price.
      IF lv_discount_pct > lv_max_discount_pct.
        lv_max_discount_pct = lv_discount_pct.
      ENDIF.
    ENDLOOP.

    DATA(lv_discount_display) = round( val = lv_max_discount_pct dec = 0 ).

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.

    IF lv_max_discount_pct > is_config-threshold_high.
      rs_check-score   = is_config-max_score.
      rs_check-passed  = abap_false.
      rs_check-message = |Discount { lv_discount_display }% exceeds allowed { is_config-threshold_high }%|.
    ELSEIF lv_max_discount_pct >= is_config-threshold_low.
      rs_check-score   = is_config-max_score * 50 / 100.
      rs_check-passed  = abap_true.
      rs_check-message = |Discount { lv_discount_display }% is close to allowed { is_config-threshold_high }%|.
    ELSE.
      rs_check-score   = 0.
      rs_check-passed  = abap_true.
      rs_check-message = |Discount { lv_discount_display }% is within acceptable range|.
    ENDIF.

  ENDMETHOD.

  METHOD check_customer_segment.

    TYPES:
      BEGIN OF ty_segment_mock,
        kunnr   TYPE kunnr,
        segment TYPE char1,
      END OF ty_segment_mock,
      ty_segment_mock_tab TYPE STANDARD TABLE OF ty_segment_mock WITH EMPTY KEY.

    " SELECT SINGLE kdgrp FROM knvv INTO @DATA(lv_kdgrp)
    "   WHERE kunnr = @iv_kunnr AND vkorg = @gv_vkorg AND vtweg = @gv_vtweg.

    DATA(lt_segment_mock) = VALUE ty_segment_mock_tab(
      ( kunnr = '0000100000' segment = 'A' )
      ( kunnr = '0000100001' segment = 'B' )
      ( kunnr = '0000100002' segment = 'C' )
    ).

    READ TABLE lt_segment_mock INTO DATA(ls_segment) WITH KEY kunnr = iv_kunnr.
    IF sy-subrc <> 0.
      ls_segment-segment = 'B'.
    ENDIF.

    rs_check-check_name = is_config-check_name.
    rs_check-max_score  = is_config-max_score.

    CASE ls_segment-segment.
      WHEN 'C'.
        rs_check-score    = is_config-max_score.
        rs_check-passed   = abap_false.
        rs_check-message  = |Customer segment: C (high risk)|.
      WHEN 'B'.
        rs_check-score    = is_config-max_score * 50 / 100.
        rs_check-passed   = abap_true.
        rs_check-message  = |Customer segment: B (medium risk)|.
      WHEN OTHERS.
        rs_check-score    = 0.
        rs_check-passed   = abap_true.
        rs_check-message  = |Customer segment: A (low risk)|.
    ENDCASE.

  ENDMETHOD.

  METHOD calculate_risk_level.

    IF iv_total_score >= zcl_order_risk_entity=>gc_score_threshold-critical.
      rv_level = zcl_order_risk_entity=>gc_risk_level-critical.
    ELSEIF iv_total_score >= zcl_order_risk_entity=>gc_score_threshold-high.
      rv_level = zcl_order_risk_entity=>gc_risk_level-high.
    ELSEIF iv_total_score >= zcl_order_risk_entity=>gc_score_threshold-medium.
      rv_level = zcl_order_risk_entity=>gc_risk_level-medium.
    ELSE.
      rv_level = zcl_order_risk_entity=>gc_risk_level-low.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
