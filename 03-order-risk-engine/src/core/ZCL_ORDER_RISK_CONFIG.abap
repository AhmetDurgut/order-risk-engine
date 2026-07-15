*&---------------------------------------------------------------------*
*& Class ZCL_ORDER_RISK_CONFIG
*&---------------------------------------------------------------------*
CLASS zcl_order_risk_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS:
      get_config
        RETURNING VALUE(rt_config) TYPE zcl_order_risk_entity=>ty_risk_configs,

      get_check_config
        IMPORTING iv_check_name    TYPE char30
        RETURNING VALUE(rs_config) TYPE zcl_order_risk_entity=>ty_risk_config.

  PRIVATE SECTION.

    METHODS:
      get_mock_config
        RETURNING VALUE(rt_config) TYPE zcl_order_risk_entity=>ty_risk_configs.

ENDCLASS.


CLASS zcl_order_risk_config IMPLEMENTATION.

  METHOD get_config.

    rt_config = get_mock_config( ).

    DELETE rt_config WHERE active = abap_false.

  ENDMETHOD.

  METHOD get_check_config.

    DATA(lt_config) = get_config( ).

    READ TABLE lt_config INTO rs_config
      WITH KEY check_name = iv_check_name.

    IF sy-subrc <> 0.
      CLEAR rs_config.
    ENDIF.

  ENDMETHOD.

  METHOD get_mock_config.

    " SELECT check_name, max_score, threshold_low, threshold_high, active
    "   FROM zorder_risk_config INTO TABLE @rt_config.

    rt_config = VALUE #(
      ( check_name = zcl_order_risk_entity=>gc_check-credit_limit
        max_score      = 25
        threshold_low  = 10
        threshold_high = 20
        active         = abap_true )
      ( check_name = zcl_order_risk_entity=>gc_check-payment_perf
        max_score      = 20
        threshold_low  = 8
        threshold_high = 15
        active         = abap_true )
      ( check_name = zcl_order_risk_entity=>gc_check-order_anomaly
        max_score      = 15
        threshold_low  = 6
        threshold_high = 12
        active         = abap_true )
      ( check_name = zcl_order_risk_entity=>gc_check-stock
        max_score      = 15
        threshold_low  = 6
        threshold_high = 12
        active         = abap_true )
      ( check_name = zcl_order_risk_entity=>gc_check-blacklist
        max_score      = 25
        threshold_low  = 0
        threshold_high = 25
        active         = abap_true )
      ( check_name = zcl_order_risk_entity=>gc_check-price_dev
        max_score      = 10
        threshold_low  = 4
        threshold_high = 8
        active         = abap_true )
      ( check_name = zcl_order_risk_entity=>gc_check-customer_seg
        max_score      = 10
        threshold_low  = 4
        threshold_high = 8
        active         = abap_true )
    ).

  ENDMETHOD.

ENDCLASS.
