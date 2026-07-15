*&---------------------------------------------------------------------*
*& Report ZORDER_RISK_MONITOR
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zorder_risk_monitor.

*&---------------------------------------------------------------------*
*& Text symbols
*&---------------------------------------------------------------------*
*   001 = 'Date Range'
*   002 = 'Risk Filters'

DATA go_alv       TYPE REF TO zcl_order_risk_alv.
DATA gv_displayed TYPE abap_bool.

SELECTION-SCREEN BEGIN OF BLOCK b01 WITH FRAME TITLE TEXT-001.
PARAMETERS p_dfrom TYPE sydatum DEFAULT sy-datum - 30.
PARAMETERS p_dto   TYPE sydatum DEFAULT sy-datum.
SELECTION-SCREEN END OF BLOCK b01.

SELECTION-SCREEN BEGIN OF BLOCK b02 WITH FRAME TITLE TEXT-002.
PARAMETERS p_risk  TYPE char10.
PARAMETERS p_kunnr TYPE kunnr.
SELECTION-SCREEN END OF BLOCK b02.

START-OF-SELECTION.

  IF p_dfrom > p_dto.
    MESSAGE 'Date from cannot be after date to' TYPE 'E'.
  ENDIF.

  go_alv = NEW zcl_order_risk_alv( ).

  CALL SCREEN 100.

*&---------------------------------------------------------------------*
*& Screen 100 setup notes
*&---------------------------------------------------------------------*
*&  - Custom control on screen 100 must be named 'ALV_CONTAINER',
*&    matching the container name used in ZCL_ORDER_RISK_ALV.
*&  - GUI status STATUS100 requires function codes BACK, EXIT, CANCEL.
*&  - Title TITLE100 = 'Order Risk Dashboard'.
*&  - gv_displayed guards against re-instantiating the ALV on every
*&    PBO cycle; it is reset when the user leaves the screen so the
*&    dashboard rebuilds on the next call with fresh selection data.
*&---------------------------------------------------------------------*

MODULE status_0100 OUTPUT.
  SET PF-STATUS 'STATUS100'.
  SET TITLEBAR 'TITLE100'.
ENDMODULE.

MODULE display_alv_0100 OUTPUT.
  IF gv_displayed = abap_false.
    go_alv->display(
      iv_date_from  = p_dfrom
      iv_date_to    = p_dto
      iv_risk_level = p_risk
      iv_kunnr      = p_kunnr ).
    gv_displayed = abap_true.
  ENDIF.
ENDMODULE.

MODULE user_command_0100 INPUT.
  CASE sy-ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANCEL'.
      gv_displayed = abap_false.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.

*&---------------------------------------------------------------------*
*& Screen 100 flow logic (maintained in the Screen Painter)
*&---------------------------------------------------------------------*
*& PROCESS BEFORE OUTPUT.
*&   MODULE status_0100.
*&   MODULE display_alv_0100.
*&
*& PROCESS AFTER INPUT.
*&   MODULE user_command_0100.
*&---------------------------------------------------------------------*
