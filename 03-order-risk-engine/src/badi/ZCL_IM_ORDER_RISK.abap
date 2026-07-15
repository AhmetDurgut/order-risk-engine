*&---------------------------------------------------------------------*
*& Class ZCL_IM_ORDER_RISK
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------*
*& WARNING - READ BEFORE USING THIS CLASS
*&---------------------------------------------------------------*
* BAdI names and method signatures for the sales order save event are NOT
* consistent across SAP releases - they differ between ECC and S/4HANA, and
* sometimes even between support packages of the same release. There is no
* single BAdI name that works everywhere, so this class does NOT implement
* a BAdI interface directly. It exposes a clean, release-independent entry
* point instead: on_order_save( ).
*
* TO WIRE THIS UP IN YOUR SYSTEM:
*   1. Go to transaction SE18 and search for whichever of these exists on
*      your system (check in this order):
*        - BADI_SD_SALES_ITEM        (S/4HANA, item-level enhancements)
*        - BADI_SALES_ORDER_SAVE     (newer S/4HANA save BAdIs)
*        - SD_SALES_DOCUMENT_SAVE    (classic ECC BAdI)
*      If none of the above exist, fall back to the classic user exit in
*      include MV45AFZZ: USEREXIT_SAVE_DOCUMENT_PREPARE.
*   2. Create (or reuse) a BAdI implementation / user exit and, inside its
*      interface method, read VBAK/VBAP (or the CHANGING/IMPORTING structures
*      the BAdI already gives you), map them to the types used here, and
*      call this class's on_order_save( ).
*   3. That adapter code is the ONLY thing that needs to change between
*      systems. Everything below - risk evaluation, logging, notification,
*      and the block decision - works as-is regardless of which BAdI you
*      end up hooking into.
*
* EXAMPLE ADAPTER (illustrative only - adjust to the BAdI you actually find):
*
*   METHOD if_ex_badi_sd_sales_item~save_document_prepare.
*
*     DATA(lo_risk) = NEW zcl_im_order_risk( ).
*
*     DATA(lt_items) = VALUE zcl_order_risk_entity=>ty_order_items(
*       FOR ls_vbap IN it_vbap
*       ( matnr = ls_vbap-matnr
*         menge = ls_vbap-kwmeng
*         netpr = ls_vbap-netpr
*         kpein = ls_vbap-kpein
*         werks = ls_vbap-werks ) ).
*
*     lo_risk->on_order_save(
*       iv_vbeln = is_vbak-vbeln
*       iv_kunnr = is_vbak-kunnr
*       it_items = lt_items ).
*
*   ENDMETHOD.
*&---------------------------------------------------------------*
CLASS zcl_im_order_risk DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS:
      constructor,

      on_order_save
        IMPORTING iv_vbeln TYPE vbeln
                  iv_kunnr TYPE kunnr
                  it_items TYPE zcl_order_risk_entity=>ty_order_items.

  PRIVATE SECTION.

    DATA mo_engine TYPE REF TO zcl_order_risk_engine.

ENDCLASS.


CLASS zcl_im_order_risk IMPLEMENTATION.

  METHOD constructor.

    mo_engine = NEW zcl_order_risk_engine( ).

  ENDMETHOD.

  METHOD on_order_save.

    DATA(ls_result) = mo_engine->evaluate_order(
      iv_vbeln = iv_vbeln
      iv_kunnr = iv_kunnr
      it_items = it_items ).

    " MESSAGE TYPE 'E' is what actually blocks the save when raised from inside
    " a BAdI - it aborts the update the same way a classic error message would.
    " LOW/MEDIUM/HIGH only inform the user; only CRITICAL stops the save.
    CASE ls_result-risk_level.
      WHEN zcl_order_risk_entity=>gc_risk_level-low.
        " No action - order saves silently.

      WHEN zcl_order_risk_entity=>gc_risk_level-medium.
        MESSAGE |Order risk: MEDIUM (score { ls_result-total_score }). Review recommended.| TYPE 'S' DISPLAY LIKE 'W'.

      WHEN zcl_order_risk_entity=>gc_risk_level-high.
        MESSAGE |Order risk: HIGH (score { ls_result-total_score }). Sales manager notified.| TYPE 'S' DISPLAY LIKE 'W'.

      WHEN zcl_order_risk_entity=>gc_risk_level-critical.
        MESSAGE |Order BLOCKED - CRITICAL risk (score { ls_result-total_score }). Senior management notified.| TYPE 'E'.
    ENDCASE.

  ENDMETHOD.

ENDCLASS.
