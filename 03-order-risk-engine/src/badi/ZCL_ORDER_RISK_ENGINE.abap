*&---------------------------------------------------------------------*
*& Class ZCL_ORDER_RISK_ENGINE
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------*
* This class never raises exceptions and never blocks an order. It evaluates,
* logs, and notifies — then hands the result back to the caller. That keeps it
* reusable from a BAdI, a batch job, a report, or a unit test. Only the BAdI
* implementation decides whether a CRITICAL result should stop the save.
*&---------------------------------------------------------------*
CLASS zcl_order_risk_engine DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS:
      constructor,

      evaluate_order
        IMPORTING iv_vbeln      TYPE vbeln
                  iv_kunnr      TYPE kunnr
                  it_items      TYPE zcl_order_risk_entity=>ty_order_items
        RETURNING VALUE(rs_result) TYPE zcl_order_risk_entity=>ty_risk_result.

  PRIVATE SECTION.

    DATA mo_checker  TYPE REF TO zcl_order_risk_checker.
    DATA mo_notifier TYPE REF TO zcl_order_risk_notifier.
    DATA mo_logger   TYPE REF TO zcl_order_risk_logger.

ENDCLASS.


CLASS zcl_order_risk_engine IMPLEMENTATION.

  METHOD constructor.

    mo_checker  = NEW zcl_order_risk_checker( ).
    mo_notifier = NEW zcl_order_risk_notifier( ).
    mo_logger   = NEW zcl_order_risk_logger( ).

  ENDMETHOD.

  METHOD evaluate_order.

    rs_result = mo_checker->evaluate(
      iv_vbeln = iv_vbeln
      iv_kunnr = iv_kunnr
      it_items = it_items ).

    mo_logger->write_log( rs_result ).

    mo_notifier->send_risk_alert( rs_result ).

  ENDMETHOD.

ENDCLASS.
