-- =====================================================================
-- ORDS handler : POST low-stock/submit          (module ba_sales_v2)
-- Source type  : PL/SQL     -- REPLACES the old low stock handler.
--
-- OPTION A (recommended first): same identity / validation as Enter
-- Sales, then calls your EXISTING procedure low_stock_submit(), so your
-- current low stock tables are used unchanged.
--
-- What changed compared with the old handler:
--   * BA is identified from the Bearer token (not from user_id in the body).
--   * location_id is checked, every sku_id is checked against BA_PRODUCTS.
--   * The JSON handed to low_stock_submit() is REBUILT on the server, with
--     the trusted user_id, so a wrong/missing id from the phone can no
--     longer break the insert.
--
-- The JSON passed to low_stock_submit():
--   {"user_id":N,"location_id":N,"stock_date":"YYYY-MM-DD",
--    "items":[{"sku_id":N,"item_code":"..","item_name":"..",
--              "question_ids":[..]}]}
-- =====================================================================
DECLARE
    l_location_id  NUMBER;
    l_stock_txt    VARCHAR2(30);
    l_stock_date   DATE;
    l_item_count   PLS_INTEGER;
    l_q_count      PLS_INTEGER;

    l_auth_header  VARCHAR2(4000);
    l_token        VARCHAR2(4000);
    l_token_hash   VARCHAR2(512);
    l_user_id      NUMBER;

    l_sku_id       NUMBER;
    l_q_id         NUMBER;
    l_dummy        NUMBER;
    l_item_code    VARCHAR2(100);
    l_item_name    VARCHAR2(4000);

    TYPE t_seen IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(40);
    l_seen         t_seen;

    -- Set to TRUE while testing to see the real Oracle error in the app.
    c_debug        CONSTANT BOOLEAN := FALSE;

    l_json         CLOB;
    l_id           NUMBER;
    l_saved        NUMBER;

    PROCEDURE send_error(
        p_status  NUMBER,
        p_message VARCHAR2
    ) IS
    BEGIN
        :status_code := p_status;
        OWA_UTIL.MIME_HEADER('application/json', FALSE);
        HTP.P('Cache-Control: no-store');
        OWA_UTIL.HTTP_HEADER_CLOSE;
        HTP.P('{"success":false,"message":' || APEX_JSON.STRINGIFY(p_message) || '}');
    END send_error;

BEGIN

    --------------------------------------------------
    -- 1. PARSE REQUEST JSON  (same style as Enter Sales)
    --    { "location_id": 12, "stock_date": "2026-11-13",
    --      "items": [ { "sku_id": 101, "question_ids": [1,3] } ] }
    --    NOTE: no user_id in the request - it comes from the token.
    --------------------------------------------------

    APEX_JSON.PARSE(:body_text);

    l_location_id := APEX_JSON.GET_NUMBER('location_id');
    l_stock_txt   := APEX_JSON.GET_VARCHAR2('stock_date');
    l_item_count  := APEX_JSON.GET_COUNT('items');

    IF l_location_id IS NULL OR l_location_id <= 0 THEN
        send_error(400, 'A valid location_id is required.');
        RETURN;
    END IF;

    IF l_stock_txt IS NULL THEN
        l_stock_date := TRUNC(SYSDATE);
    ELSE
        BEGIN
            l_stock_date := TO_DATE(l_stock_txt, 'FXYYYY-MM-DD');
        EXCEPTION
            WHEN OTHERS THEN
                send_error(400, 'Invalid stock_date. Use YYYY-MM-DD.');
                RETURN;
        END;
    END IF;

    IF l_item_count IS NULL OR l_item_count < 1 THEN
        send_error(400, 'At least one low stock item is required.');
        RETURN;
    END IF;

    IF l_item_count > 500 THEN
        send_error(400, 'A maximum of 500 items is allowed per submission.');
        RETURN;
    END IF;

    --------------------------------------------------
    -- AUTHENTICATE: Bearer token -> active BA (same as Enter Sales)
    --------------------------------------------------

    l_auth_header := OWA_UTIL.GET_CGI_ENV('HTTP_AUTHORIZATION');

    IF l_auth_header IS NULL THEN
        l_auth_header := OWA_UTIL.GET_CGI_ENV('Authorization');
    END IF;

    IF l_auth_header IS NULL THEN
        l_auth_header := OWA_UTIL.GET_CGI_ENV('REDIRECT_HTTP_AUTHORIZATION');
    END IF;

    IF l_auth_header IS NULL
       OR UPPER(SUBSTR(TRIM(l_auth_header), 1, 7)) <> 'BEARER '
    THEN
        send_error(401, 'Authorization Bearer token is required.');
        RETURN;
    END IF;

    l_token := TRIM(SUBSTR(TRIM(l_auth_header), 8));

    IF l_token IS NULL THEN
        send_error(401, 'Authorization token is invalid.');
        RETURN;
    END IF;

    l_token_hash := APEX_UTIL.GET_HASH(
        APEX_T_VARCHAR2('BA_SALES_SESSION_V1', l_token),
        FALSE
    );

    BEGIN
        SELECT s.USER_ID
          INTO l_user_id
          FROM HRMS.BA_SALES_SESSIONS s
          JOIN HRMS.BA_SALES_USERS u
            ON u.USER_ID = s.USER_ID
         WHERE s.TOKEN_HASH = l_token_hash
           AND s.REVOKED_AT IS NULL
           AND s.EXPIRES_AT > SYSTIMESTAMP
           AND UPPER(u.STATUS) = 'ACTIVE'
           AND UPPER(u.ROLE_CODE) = 'BA';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            send_error(401, 'Session is invalid, expired, or not authorized for BA sales.');
            RETURN;
        WHEN TOO_MANY_ROWS THEN
            send_error(401, 'Session is invalid.');
            RETURN;
    END;

    --------------------------------------------------
    -- LOCATION MUST EXIST
    --------------------------------------------------

    BEGIN
        SELECT 1
          INTO l_dummy
          FROM HRMS.BA_SALES_LOCATIONS
         WHERE LOCATION_ID = l_location_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            send_error(400, 'The specified location does not exist.');
            RETURN;
        WHEN TOO_MANY_ROWS THEN
            send_error(400, 'The specified location is invalid.');
            RETURN;
    END;

    --------------------------------------------------
    -- VALIDATE EVERY SKU (source: BA_PRODUCTS, same as Enter Sales)
    --------------------------------------------------

    FOR i IN 1 .. l_item_count LOOP

        l_sku_id := APEX_JSON.GET_NUMBER('items[%d].sku_id', i);

        IF l_sku_id IS NULL OR l_sku_id <= 0 THEN
            send_error(400, 'Each item requires a valid sku_id.');
            RETURN;
        END IF;

        IF l_seen.EXISTS(TO_CHAR(l_sku_id)) THEN
            send_error(400, 'The same product was sent more than once.');
            RETURN;
        END IF;
        l_seen(TO_CHAR(l_sku_id)) := 1;

        BEGIN
            SELECT 1
              INTO l_dummy
              FROM BA_PRODUCTS
             WHERE SKU_ID = l_sku_id
               AND UPPER(TRIM(ACTIVE_FLAG)) = 'Y';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                send_error(400, 'An item contains an invalid or inactive SKU.');
                RETURN;
            WHEN TOO_MANY_ROWS THEN
                send_error(400, 'Duplicate SKU records found in BA_PRODUCTS.');
                RETURN;
        END;

        l_q_count := NVL(APEX_JSON.GET_COUNT('items[%d].question_ids', i), 0);

        IF l_q_count > 100 THEN
            send_error(400, 'Too many review questions for one item.');
            RETURN;
        END IF;

        FOR j IN 1 .. l_q_count LOOP
            l_q_id := APEX_JSON.GET_NUMBER('items[%d].question_ids[%d]', i, j);
            IF l_q_id IS NULL OR l_q_id <= 0 THEN
                send_error(400, 'Each question id must be a positive number.');
                RETURN;
            END IF;
        END LOOP;

    END LOOP;

    --------------------------------------------------
    -- BUILD THE CLEAN JSON (trusted ids)
    --------------------------------------------------

    APEX_JSON.INITIALIZE_CLOB_OUTPUT;
    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('user_id',     l_user_id);
    APEX_JSON.WRITE('location_id', l_location_id);
    APEX_JSON.WRITE('stock_date',  TO_CHAR(l_stock_date, 'YYYY-MM-DD'));
    APEX_JSON.OPEN_ARRAY('items');

    FOR i IN 1 .. l_item_count LOOP

        l_sku_id := APEX_JSON.GET_NUMBER('items[%d].sku_id', i);

        SELECT SKU_CODE, UNIQUE_NAME
          INTO l_item_code, l_item_name
          FROM BA_PRODUCTS
         WHERE SKU_ID = l_sku_id
           AND UPPER(TRIM(ACTIVE_FLAG)) = 'Y';

        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('sku_id',    l_sku_id);
        APEX_JSON.WRITE('item_code', l_item_code);
        APEX_JSON.WRITE('item_name', l_item_name);
        APEX_JSON.OPEN_ARRAY('question_ids');

        FOR j IN 1 .. NVL(APEX_JSON.GET_COUNT('items[%d].question_ids', i), 0) LOOP
            APEX_JSON.WRITE(APEX_JSON.GET_NUMBER('items[%d].question_ids[%d]', i, j));
        END LOOP;

        APEX_JSON.CLOSE_ARRAY;
        APEX_JSON.CLOSE_OBJECT;

    END LOOP;

    APEX_JSON.CLOSE_ARRAY;
    APEX_JSON.CLOSE_OBJECT;

    l_json := APEX_JSON.GET_CLOB_OUTPUT;
    APEX_JSON.FREE_OUTPUT;

    --------------------------------------------------
    -- SAVE THROUGH THE EXISTING PROCEDURE
    --------------------------------------------------

    low_stock_submit(l_json, l_id, l_saved);

    COMMIT;

    :status_code := 201;

    OWA_UTIL.MIME_HEADER('application/json', FALSE);
    HTP.P('Cache-Control: no-store');
    OWA_UTIL.HTTP_HEADER_CLOSE;

    HTP.P(
        '{"success":true,"status":"success",' ||
        '"message":"Low stock submitted successfully.",' ||
        '"id":'    || TO_CHAR(l_id,    'FM9999999999999999990') ||
        ',"items":' || TO_CHAR(l_saved, 'FM9999990') ||
        '}'
    );

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        IF c_debug THEN
            send_error(500, SQLERRM);
        ELSE
            send_error(500, 'Unable to submit low stock. Check the ORDS error log for details.');
        END IF;
END;
