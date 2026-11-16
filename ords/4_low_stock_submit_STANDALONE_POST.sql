-- =====================================================================
-- OPTION B (use ONLY if Option A still fails inside low_stock_submit(),
-- e.g. that procedure checks ids against an old table): fully
-- self-contained, exactly like the Enter Sales handler. It writes into
-- three NEW tables, so run the DDL below once first.
-- Questions are stored as plain ids (no foreign key to the review table
-- because its name is not known here - add one if you like).
-- =====================================================================

/* ----------------------------- RUN ONCE (DDL) -----------------------------

CREATE TABLE HRMS.BA_LOWSTOCK_V2_REPORTS (
    REPORT_ID    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    USER_ID      NUMBER NOT NULL,
    LOCATION_ID  NUMBER NOT NULL,
    STOCK_DATE   DATE   NOT NULL,
    CREATED_AT   TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE TABLE HRMS.BA_LOWSTOCK_V2_ITEMS (
    ITEM_ID      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    REPORT_ID    NUMBER NOT NULL REFERENCES HRMS.BA_LOWSTOCK_V2_REPORTS (REPORT_ID),
    SKU_ID       NUMBER NOT NULL,
    ITEM_CODE    VARCHAR2(100),
    ITEM_NAME    VARCHAR2(4000)
);

CREATE TABLE HRMS.BA_LOWSTOCK_V2_ANSWERS (
    ITEM_ID      NUMBER NOT NULL REFERENCES HRMS.BA_LOWSTOCK_V2_ITEMS (ITEM_ID),
    QUESTION_ID  NUMBER NOT NULL,
    CONSTRAINT BA_LOWSTOCK_V2_ANS_PK PRIMARY KEY (ITEM_ID, QUESTION_ID)
);

---------------------------------------------------------------------------- */

-- ORDS handler : POST low-stock/submit          (module ba_sales_v2)
-- Source type  : PL/SQL
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

    l_id           NUMBER;
    l_item_id      NUMBER;
    l_saved        NUMBER := 0;

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
    -- INSERT REPORT HEADER
    --------------------------------------------------

    INSERT INTO HRMS.BA_LOWSTOCK_V2_REPORTS (USER_ID, LOCATION_ID, STOCK_DATE)
    VALUES (l_user_id, l_location_id, l_stock_date)
    RETURNING REPORT_ID INTO l_id;

    --------------------------------------------------
    -- INSERT ITEMS + TICKED QUESTIONS
    --------------------------------------------------

    FOR i IN 1 .. l_item_count LOOP

        l_sku_id := APEX_JSON.GET_NUMBER('items[%d].sku_id', i);

        SELECT SKU_CODE, UNIQUE_NAME
          INTO l_item_code, l_item_name
          FROM BA_PRODUCTS
         WHERE SKU_ID = l_sku_id
           AND UPPER(TRIM(ACTIVE_FLAG)) = 'Y';

        INSERT INTO HRMS.BA_LOWSTOCK_V2_ITEMS (REPORT_ID, SKU_ID, ITEM_CODE, ITEM_NAME)
        VALUES (l_id, l_sku_id, l_item_code, l_item_name)
        RETURNING ITEM_ID INTO l_item_id;

        l_saved := l_saved + 1;

        FOR j IN 1 .. NVL(APEX_JSON.GET_COUNT('items[%d].question_ids', i), 0) LOOP
            l_q_id := APEX_JSON.GET_NUMBER('items[%d].question_ids[%d]', i, j);
            BEGIN
                INSERT INTO HRMS.BA_LOWSTOCK_V2_ANSWERS (ITEM_ID, QUESTION_ID)
                VALUES (l_item_id, l_q_id);
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN NULL;  -- same question ticked twice
            END;
        END LOOP;

    END LOOP;

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
