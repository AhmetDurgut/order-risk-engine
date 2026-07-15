*&---------------------------------------------------------------------*
*& Class ZCL_ORDER_RISK_ALV
*&---------------------------------------------------------------------*
CLASS zcl_order_risk_alv DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor.

    METHODS display
      IMPORTING iv_date_from  TYPE sydatum
                iv_date_to    TYPE sydatum
                iv_risk_level TYPE char10
                iv_kunnr      TYPE kunnr.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_dashboard_line,
        vbeln       TYPE vbeln,
        kunnr       TYPE kunnr,
        total_score TYPE i,
        risk_level  TYPE char10,
        action      TYPE char20,
        uname       TYPE syuname,
        datum       TYPE sydatum,
        uzeit       TYPE syuzeit,
        row_color   TYPE char3,
      END OF ty_dashboard_line,
      ty_dashboard_lines TYPE STANDARD TABLE OF ty_dashboard_line WITH EMPTY KEY.

    CONSTANTS gc_fcode_approve TYPE ui_func VALUE 'APPROVE'.
    CONSTANTS gc_fcode_reject  TYPE ui_func VALUE 'REJECT'.
    CONSTANTS gc_fcode_details TYPE ui_func VALUE 'SHOW_DETAILS'.
    CONSTANTS gc_fcode_export  TYPE ui_func VALUE 'EXCEL_EXPORT'.

    DATA mo_container TYPE REF TO cl_gui_custom_container.
    DATA mo_grid       TYPE REF TO cl_gui_alv_grid.
    DATA mt_alv_data   TYPE ty_dashboard_lines.
    DATA mt_raw_logs   TYPE zcl_order_risk_entity=>ty_risk_logs.
    DATA mo_logger     TYPE REF TO zcl_order_risk_logger.

    METHODS get_log_data
      IMPORTING iv_date_from  TYPE sydatum
                iv_date_to    TYPE sydatum
                iv_risk_level TYPE char10
                iv_kunnr      TYPE kunnr
      RETURNING VALUE(rt_logs) TYPE zcl_order_risk_entity=>ty_risk_logs.

    METHODS build_dashboard_data
      IMPORTING it_logs        TYPE zcl_order_risk_entity=>ty_risk_logs
      RETURNING VALUE(rt_lines) TYPE ty_dashboard_lines.

    METHODS build_fieldcatalog
      RETURNING VALUE(rt_fcat) TYPE lvc_t_fcat.

    METHODS add_fcat_entry
      IMPORTING iv_fieldname   TYPE lvc_s_fcat-fieldname
                iv_text        TYPE string
                iv_outputlen   TYPE lvc_s_fcat-outputlen DEFAULT 0
                iv_col_pos     TYPE lvc_s_fcat-col_pos
                iv_cfieldname  TYPE lvc_s_fcat-cfieldname OPTIONAL
                iv_do_sum      TYPE lvc_s_fcat-do_sum OPTIONAL
      RETURNING VALUE(rs_fcat) TYPE lvc_s_fcat.

    METHODS build_layout
      RETURNING VALUE(rs_layout) TYPE lvc_s_layo.

    METHODS register_events.

    METHODS export_to_excel.

    METHODS show_check_details
      IMPORTING iv_vbeln TYPE vbeln.

    METHODS on_toolbar
        FOR EVENT toolbar OF cl_gui_alv_grid
      IMPORTING e_object.

    METHODS on_user_command
        FOR EVENT user_command OF cl_gui_alv_grid
      IMPORTING e_ucomm.

ENDCLASS.


CLASS zcl_order_risk_alv IMPLEMENTATION.


  METHOD constructor.

    mo_logger = NEW zcl_order_risk_logger( ).

  ENDMETHOD.


  METHOD display.

    IF mo_container IS NOT BOUND.
      mo_container = NEW cl_gui_custom_container( container_name = 'ALV_CONTAINER' ).
      mo_grid      = NEW cl_gui_alv_grid( i_parent = mo_container ).
      register_events( ).
    ENDIF.

    mt_raw_logs = get_log_data(
      iv_date_from  = iv_date_from
      iv_date_to    = iv_date_to
      iv_risk_level = iv_risk_level
      iv_kunnr      = iv_kunnr ).

    mt_alv_data = build_dashboard_data( mt_raw_logs ).

    DATA(lt_fcat)   = build_fieldcatalog( ).
    DATA(ls_layout) = build_layout( ).

    mo_grid->set_table_for_first_display(
      EXPORTING
        is_layout       = ls_layout
      CHANGING
        it_outtab       = mt_alv_data
        it_fieldcatalog = lt_fcat ).

  ENDMETHOD.


  METHOD get_log_data.

    "SELECT * FROM zorder_risk_log
    "  WHERE datum BETWEEN @iv_date_from AND @iv_date_to
    "    AND ( @iv_risk_level IS INITIAL OR risk_level = @iv_risk_level )
    "    AND ( @iv_kunnr IS INITIAL OR kunnr = @iv_kunnr )
    "  INTO TABLE @rt_logs.

    DATA(lv_datum_1) = sy-datum - 2.
    DATA(lv_datum_2) = sy-datum - 1.
    DATA(lv_datum_3) = sy-datum.

    DATA(lt_mock) = VALUE zcl_order_risk_entity=>ty_risk_logs(

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-credit_limit score = 25
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Credit usage at 118% of limit'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-payment_perf score = 20
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Avg payment delay: 25 days'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-order_anomaly score = 6
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Order 118% of 3-month average'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-stock score = 4
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Insufficient stock for 1 of 3 items'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-blacklist score = 25
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Customer/material combination is restricted'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-price_dev score = 2
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Discount 9% is close to allowed 15%'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012345' kunnr = '0000100002'
        check_name = zcl_order_risk_entity=>gc_check-customer_seg score = 10
        risk_level = zcl_order_risk_entity=>gc_risk_level-critical
        message = 'Customer segment: C (high risk)'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_1 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-credit_limit score = 18
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'Credit usage at 92% of limit'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-payment_perf score = 12
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'Avg payment delay: 12 days'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-order_anomaly score = 11
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'Order 124% of 3-month average'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-stock score = 12
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'Insufficient stock for 3 of 4 items'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-blacklist score = 0
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'No blacklist match'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-price_dev score = 10
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'Discount 9% exceeds allowed 8%'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012346' kunnr = '0000100001'
        check_name = zcl_order_risk_entity=>gc_check-customer_seg score = 5
        risk_level = zcl_order_risk_entity=>gc_risk_level-high
        message = 'Customer segment: B (medium risk)'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_2 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-credit_limit score = 0
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'Credit usage at 22% of limit'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-payment_perf score = 0
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'Avg payment delay: 2 days'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-order_anomaly score = 3
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'Order 108% of 3-month average'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-stock score = 5
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'Insufficient stock for 1 of 5 items'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-blacklist score = 0
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'No blacklist match'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-price_dev score = 4
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'Discount 5% is close to allowed 8%'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

      ( log_id = cl_system_uuid=>create_uuid_c32_static( ) vbeln = '0000012347' kunnr = '0000100000'
        check_name = zcl_order_risk_entity=>gc_check-customer_seg score = 0
        risk_level = zcl_order_risk_entity=>gc_risk_level-low
        message = 'Customer segment: A (low risk)'
        action = zcl_order_risk_entity=>gc_action-risk_evaluated
        uname = sy-uname datum = lv_datum_3 uzeit = sy-uzeit )

    ).

    rt_logs = lt_mock.

    DELETE rt_logs WHERE datum < iv_date_from OR datum > iv_date_to.

    IF iv_risk_level IS NOT INITIAL.
      DELETE rt_logs WHERE risk_level <> iv_risk_level.
    ENDIF.

    IF iv_kunnr IS NOT INITIAL.
      DELETE rt_logs WHERE kunnr <> iv_kunnr.
    ENDIF.

  ENDMETHOD.


  METHOD build_dashboard_data.

    DATA(lt_sorted) = it_logs.
    SORT lt_sorted BY vbeln.

    LOOP AT lt_sorted ASSIGNING FIELD-SYMBOL(<ls_log>)
         GROUP BY <ls_log>-vbeln
         ASSIGNING FIELD-SYMBOL(<ls_group>).

      DATA(ls_line) = VALUE ty_dashboard_line(
        vbeln  = <ls_group>
        action = zcl_order_risk_entity=>gc_action-risk_evaluated ).

      DATA(lv_latest_action_key) = ''.

      LOOP AT GROUP <ls_group> ASSIGNING FIELD-SYMBOL(<ls_member>).

        IF <ls_member>-check_name IS NOT INITIAL.
          ls_line-total_score = ls_line-total_score + <ls_member>-score.
          ls_line-kunnr       = <ls_member>-kunnr.
          ls_line-risk_level  = <ls_member>-risk_level.
          ls_line-uname       = <ls_member>-uname.
          ls_line-datum       = <ls_member>-datum.
          ls_line-uzeit       = <ls_member>-uzeit.

        ELSEIF <ls_member>-action = zcl_order_risk_entity=>gc_action-approved
            OR <ls_member>-action = zcl_order_risk_entity=>gc_action-rejected.

          DATA(lv_action_key) = |{ <ls_member>-datum }{ <ls_member>-uzeit }|.
          IF lv_action_key >= lv_latest_action_key.
            lv_latest_action_key = lv_action_key.
            ls_line-action       = <ls_member>-action.
          ENDIF.
        ENDIF.

      ENDLOOP.

      ls_line-row_color = SWITCH #( ls_line-risk_level
        WHEN zcl_order_risk_entity=>gc_risk_level-low      THEN zcl_order_risk_entity=>gc_color-low
        WHEN zcl_order_risk_entity=>gc_risk_level-medium   THEN zcl_order_risk_entity=>gc_color-medium
        WHEN zcl_order_risk_entity=>gc_risk_level-high     THEN zcl_order_risk_entity=>gc_color-high
        WHEN zcl_order_risk_entity=>gc_risk_level-critical THEN zcl_order_risk_entity=>gc_color-critical ).

      APPEND ls_line TO rt_lines.

    ENDLOOP.

    TYPES:
      BEGIN OF ty_sort_helper,
        rank TYPE i,
        line TYPE ty_dashboard_line,
      END OF ty_sort_helper.

    DATA(lt_sort_helper) = VALUE STANDARD TABLE OF ty_sort_helper(
      FOR ls_result IN rt_lines
      ( rank = SWITCH i( ls_result-risk_level
                  WHEN zcl_order_risk_entity=>gc_risk_level-critical THEN 1
                  WHEN zcl_order_risk_entity=>gc_risk_level-high     THEN 2
                  WHEN zcl_order_risk_entity=>gc_risk_level-medium   THEN 3
                  WHEN zcl_order_risk_entity=>gc_risk_level-low      THEN 4
                  ELSE 5 )
        line = ls_result ) ).

    SORT lt_sort_helper BY rank ASCENDING line-vbeln ASCENDING.

    rt_lines = VALUE #( FOR ls_helper IN lt_sort_helper ( ls_helper-line ) ).

  ENDMETHOD.


  METHOD build_fieldcatalog.
    rt_fcat = VALUE lvc_t_fcat(
      ( add_fcat_entry( iv_fieldname = 'VBELN'       iv_text = 'Sales Order'   iv_outputlen = 12 iv_col_pos = 1 ) )
      ( add_fcat_entry( iv_fieldname = 'KUNNR'       iv_text = 'Customer'      iv_outputlen = 12 iv_col_pos = 2 ) )
      ( add_fcat_entry( iv_fieldname = 'TOTAL_SCORE' iv_text = 'Risk Score'    iv_outputlen = 10 iv_col_pos = 3 ) )
      ( add_fcat_entry( iv_fieldname = 'RISK_LEVEL'  iv_text = 'Risk Level'    iv_outputlen = 10 iv_col_pos = 4 ) )
      ( add_fcat_entry( iv_fieldname = 'ACTION'      iv_text = 'Status'        iv_outputlen = 16 iv_col_pos = 5 ) )
      ( add_fcat_entry( iv_fieldname = 'UNAME'       iv_text = 'Evaluated By'  iv_outputlen = 12 iv_col_pos = 6 ) )
      ( add_fcat_entry( iv_fieldname = 'DATUM'       iv_text = 'Date'          iv_outputlen = 10 iv_col_pos = 7 ) )
      ( add_fcat_entry( iv_fieldname = 'UZEIT'       iv_text = 'Time'          iv_outputlen = 10 iv_col_pos = 8 ) )
    ).
  ENDMETHOD.


  METHOD add_fcat_entry.

    rs_fcat-fieldname  = iv_fieldname.
    rs_fcat-scrtext_l  = iv_text.
    rs_fcat-scrtext_m  = iv_text.
    rs_fcat-scrtext_s  = iv_text.
    rs_fcat-reptext    = iv_text.
    rs_fcat-outputlen  = iv_outputlen.
    rs_fcat-col_pos    = iv_col_pos.
    rs_fcat-cfieldname = iv_cfieldname.
    rs_fcat-do_sum     = iv_do_sum.

  ENDMETHOD.


  METHOD build_layout.

    rs_layout-info_fname = 'ROW_COLOR'.
    rs_layout-zebra      = abap_true.
    rs_layout-cwidth_opt = abap_true.
    rs_layout-sel_mode   = 'A'.

  ENDMETHOD.


  METHOD register_events.

    SET HANDLER on_toolbar      FOR mo_grid.
    SET HANDLER on_user_command FOR mo_grid.

  ENDMETHOD.


  METHOD export_to_excel.

    DATA lv_fullpath TYPE string.
    DATA lv_path     TYPE string.
    DATA lv_filename TYPE string.
    DATA lt_raw      TYPE TABLE OF string.

    cl_gui_frontend_services=>file_save_dialog(
      EXPORTING
        window_title       = 'Export Order Risk Dashboard'
        default_extension  = 'XLSX'
        default_file_name  = 'order_risk_dashboard'
        file_filter        = 'Excel Files (*.XLSX)|*.XLSX|All Files (*.*)|*.*'
      CHANGING
        filename           = lv_filename
        path               = lv_path
        fullpath           = lv_fullpath
      EXCEPTIONS
        OTHERS             = 1 ).

    IF sy-subrc <> 0 OR lv_fullpath IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_tab) = cl_abap_char_utilities=>horizontal_tab.

    APPEND |Sales Order{ lv_tab }Customer{ lv_tab }Risk Score{ lv_tab }Risk Level{ lv_tab }| &&
           |Status{ lv_tab }Evaluated By{ lv_tab }Date{ lv_tab }Time| TO lt_raw.

    LOOP AT mt_alv_data INTO DATA(ls_row).
      APPEND |{ ls_row-vbeln }{ lv_tab }{ ls_row-kunnr }{ lv_tab }{ ls_row-total_score }{ lv_tab }{ ls_row-risk_level }{ lv_tab }| &&
             |{ ls_row-action }{ lv_tab }{ ls_row-uname }{ lv_tab }{ ls_row-datum }{ lv_tab }{ ls_row-uzeit }| TO lt_raw.
    ENDLOOP.

    cl_gui_frontend_services=>gui_download(
      EXPORTING
        filename = lv_fullpath
        filetype = 'ASC'
        codepage = '4110'
      CHANGING
        data_tab = lt_raw
      EXCEPTIONS
        OTHERS   = 24 ).

    IF sy-subrc <> 0.
      MESSAGE 'Export to Excel failed' TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE 'Export completed successfully' TYPE 'S'.
    ENDIF.

  ENDMETHOD.


  METHOD show_check_details.

    DATA(lt_details) = VALUE zcl_order_risk_entity=>ty_risk_logs(
      FOR ls_log IN mt_raw_logs
      WHERE ( vbeln = iv_vbeln AND check_name IS NOT INITIAL )
      ( ls_log ) ).

    IF lt_details IS INITIAL.
      MESSAGE 'No check details found for this order' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    TYPES:
      BEGIN OF ty_detail_line,
        check_name TYPE char30,
        score      TYPE i,
        risk_level TYPE char10,
        message    TYPE char100,
      END OF ty_detail_line.

    DATA(lt_display) = VALUE STANDARD TABLE OF ty_detail_line(
      FOR ls_detail IN lt_details
      ( check_name = ls_detail-check_name
        score      = ls_detail-score
        risk_level = ls_detail-risk_level
        message    = ls_detail-message ) ).

    TRY.
        cl_salv_table=>factory(
          EXPORTING
            list_display = abap_false
          IMPORTING
            r_salv_table = DATA(lo_salv)
          CHANGING
            t_table      = lt_display ).

        lo_salv->get_columns( )->set_optimize( abap_true ).

        lo_salv->get_display_settings( )->set_list_header( |Check Details - Order { iv_vbeln }| ).

        lo_salv->set_screen_popup(
          start_column = 20
          end_column   = 120
          start_line   = 5
          end_line     = 20 ).

        lo_salv->display( ).

      CATCH cx_salv_msg.
        MESSAGE 'Unable to display check details' TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.

  ENDMETHOD.


  METHOD on_toolbar.

    APPEND VALUE stb_button( butn_type = 3 ) TO e_object->mt_toolbar.

    APPEND VALUE stb_button(
      function  = gc_fcode_approve
      icon      = icon_okay
      quickinfo = 'Approve Order'
      text      = 'Approve Order'
      butn_type = 0 ) TO e_object->mt_toolbar.

    APPEND VALUE stb_button(
      function  = gc_fcode_reject
      icon      = icon_cancel
      quickinfo = 'Reject Order'
      text      = 'Reject Order'
      butn_type = 0 ) TO e_object->mt_toolbar.

    APPEND VALUE stb_button(
      function  = gc_fcode_details
      icon      = icon_display
      quickinfo = 'Show Check Details'
      text      = 'Show Check Details'
      butn_type = 0 ) TO e_object->mt_toolbar.

    APPEND VALUE stb_button(
      function  = gc_fcode_export
      icon      = icon_xxl_export
      quickinfo = 'Export to Excel'
      text      = 'Export to Excel'
      butn_type = 0 ) TO e_object->mt_toolbar.

  ENDMETHOD.


  METHOD on_user_command.

    DATA lt_rows TYPE lvc_t_row.

    mo_grid->get_selected_rows( IMPORTING et_index_rows = lt_rows ).

    IF lt_rows IS INITIAL
       AND ( e_ucomm = gc_fcode_approve OR e_ucomm = gc_fcode_reject OR e_ucomm = gc_fcode_details ).
      MESSAGE 'Please select at least one row' TYPE 'S' DISPLAY LIKE 'W'.
      RETURN.
    ENDIF.

    CASE e_ucomm.

      WHEN gc_fcode_approve.

        LOOP AT lt_rows INTO DATA(ls_row_approve).
          ASSIGN mt_alv_data[ ls_row_approve-index ] TO FIELD-SYMBOL(<ls_approve>).
          mo_logger->write_action_log(
            iv_vbeln  = <ls_approve>-vbeln
            iv_kunnr  = <ls_approve>-kunnr
            iv_action = zcl_order_risk_entity=>gc_action-approved ).
          <ls_approve>-action = zcl_order_risk_entity=>gc_action-approved.
        ENDLOOP.

        mo_grid->refresh_table_display( ).

      WHEN gc_fcode_reject.

        LOOP AT lt_rows INTO DATA(ls_row_reject).
          ASSIGN mt_alv_data[ ls_row_reject-index ] TO FIELD-SYMBOL(<ls_reject>).
          mo_logger->write_action_log(
            iv_vbeln  = <ls_reject>-vbeln
            iv_kunnr  = <ls_reject>-kunnr
            iv_action = zcl_order_risk_entity=>gc_action-rejected ).
          <ls_reject>-action = zcl_order_risk_entity=>gc_action-rejected.
        ENDLOOP.

        mo_grid->refresh_table_display( ).

      WHEN gc_fcode_details.

        DATA(ls_first) = mt_alv_data[ lt_rows[ 1 ]-index ].
        show_check_details( ls_first-vbeln ).

      WHEN gc_fcode_export.

        export_to_excel( ).

    ENDCASE.

  ENDMETHOD.

ENDCLASS.
