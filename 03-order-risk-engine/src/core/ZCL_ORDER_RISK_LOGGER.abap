*&---------------------------------------------------------------------*
*& Class ZCL_ORDER_RISK_LOGGER
*&---------------------------------------------------------------------*
CLASS zcl_order_risk_logger DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS:
      write_log
        IMPORTING is_result TYPE zcl_order_risk_entity=>ty_risk_result,

      write_action_log
        IMPORTING iv_vbeln  TYPE vbeln
                  iv_kunnr  TYPE kunnr
                  iv_action TYPE char20.

ENDCLASS.


CLASS zcl_order_risk_logger IMPLEMENTATION.

  METHOD write_log.

    DATA lt_logs TYPE zcl_order_risk_entity=>ty_risk_logs.

    LOOP AT is_result-checks ASSIGNING FIELD-SYMBOL(<ls_check>).

      APPEND VALUE #(
        log_id     = cl_system_uuid=>create_uuid_c32_static( )
        vbeln      = is_result-vbeln
        kunnr      = is_result-kunnr
        check_name = <ls_check>-check_name
        score      = <ls_check>-score
        risk_level = is_result-risk_level
        message    = <ls_check>-message
        action     = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname      = sy-uname
        datum      = sy-datum
        uzeit      = sy-uzeit ) TO lt_logs.

    ENDLOOP.

    "INSERT zorder_risk_log FROM TABLE @lt_logs.
    "IF sy-subrc <> 0.
    "  MESSAGE 'Risk log could not be written' TYPE 'S' DISPLAY LIKE 'E'.
    "ENDIF.

    MESSAGE |Risk log written: { lines( lt_logs ) } entries for order { is_result-vbeln }| TYPE 'S'.

  ENDMETHOD.

  METHOD write_action_log.

    DATA(ls_log) = VALUE zcl_order_risk_entity=>ty_risk_log(
      log_id     = cl_system_uuid=>create_uuid_c32_static( )
      vbeln      = iv_vbeln
      kunnr      = iv_kunnr
      check_name = ''
      score      = 0
      risk_level = ''
      message    = |Order { iv_action } by user|
      action     = iv_action
      uname      = sy-uname
      datum      = sy-datum
      uzeit      = sy-uzeit ).

    "INSERT zorder_risk_log FROM @ls_log.

    MESSAGE |Action logged: { iv_action } for order { iv_vbeln }| TYPE 'S'.

  ENDMETHOD.

ENDCLASS.
