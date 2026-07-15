*&---------------------------------------------------------------------*
*& Class ZCL_ORDER_RISK_ENTITY
*&---------------------------------------------------------------------*
CLASS zcl_order_risk_entity DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_order_item,
        matnr TYPE matnr,
        menge TYPE menge_d,
        netpr TYPE netpr,
        kpein TYPE kpein,
        werks TYPE werks,
      END OF ty_order_item,
      ty_order_items TYPE STANDARD TABLE OF ty_order_item WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_risk_check,
        check_name TYPE char30,
        score      TYPE i,
        max_score  TYPE i,
        passed     TYPE abap_bool,
        message    TYPE char100,
      END OF ty_risk_check,
      ty_risk_checks TYPE STANDARD TABLE OF ty_risk_check WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_risk_result,
        vbeln       TYPE vbeln,
        kunnr       TYPE kunnr,
        total_score TYPE i,
        risk_level  TYPE char10,
        checks      TYPE ty_risk_checks,
      END OF ty_risk_result.

    TYPES:
      BEGIN OF ty_risk_config,
        check_name      TYPE char30,
        max_score       TYPE i,
        threshold_low   TYPE i,
        threshold_high  TYPE i,
        active          TYPE abap_bool,
      END OF ty_risk_config,
      ty_risk_configs TYPE STANDARD TABLE OF ty_risk_config WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_risk_log,
        log_id     TYPE sysuuid_c,
        vbeln      TYPE vbeln,
        kunnr      TYPE kunnr,
        check_name TYPE char30,
        score      TYPE i,
        risk_level TYPE char10,
        message    TYPE char100,
        action     TYPE char20,
        uname      TYPE syuname,
        datum      TYPE sydatum,
        uzeit      TYPE syuzeit,
      END OF ty_risk_log,
      ty_risk_logs TYPE STANDARD TABLE OF ty_risk_log WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_blacklist,
        kunnr  TYPE kunnr,
        matnr  TYPE matnr,
        reason TYPE char100,
        active TYPE abap_bool,
      END OF ty_blacklist,
      ty_blacklist_tab TYPE STANDARD TABLE OF ty_blacklist WITH EMPTY KEY.

    CONSTANTS:
      BEGIN OF gc_risk_level,
        low      TYPE char10 VALUE 'LOW',
        medium   TYPE char10 VALUE 'MEDIUM',
        high     TYPE char10 VALUE 'HIGH',
        critical TYPE char10 VALUE 'CRITICAL',
      END OF gc_risk_level.

    CONSTANTS:
      BEGIN OF gc_color,
        low      TYPE char3 VALUE 'C51',
        medium   TYPE char3 VALUE 'C31',
        high     TYPE char3 VALUE 'C61',
        critical TYPE char3 VALUE 'C71',
      END OF gc_color.

    CONSTANTS:
      BEGIN OF gc_score_threshold,
        medium   TYPE i VALUE 31,
        high     TYPE i VALUE 61,
        critical TYPE i VALUE 86,
      END OF gc_score_threshold.

    CONSTANTS:
      BEGIN OF gc_action,
        risk_evaluated TYPE char20 VALUE 'RISK_EVALUATED',
        approved       TYPE char20 VALUE 'APPROVED',
        rejected       TYPE char20 VALUE 'REJECTED',
      END OF gc_action.

    CONSTANTS:
      BEGIN OF gc_check,
        credit_limit  TYPE char30 VALUE 'CREDIT_LIMIT',
        payment_perf  TYPE char30 VALUE 'PAYMENT_PERF',
        order_anomaly TYPE char30 VALUE 'ORDER_ANOMALY',
        stock         TYPE char30 VALUE 'STOCK',
        blacklist     TYPE char30 VALUE 'BLACKLIST',
        price_dev     TYPE char30 VALUE 'PRICE_DEV',
        customer_seg  TYPE char30 VALUE 'CUSTOMER_SEG',
      END OF gc_check.

ENDCLASS.


CLASS zcl_order_risk_entity IMPLEMENTATION.
ENDCLASS.
