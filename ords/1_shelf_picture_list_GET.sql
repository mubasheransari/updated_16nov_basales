-- =====================================================================
-- ORDS handler : GET  shelf-picture/list        (module ba_sales_v2)
-- Source type  : PL/SQL
-- Parameters   : page       (URI query, INTEGER)  default 1
--                page_size  (URI query, INTEGER)  default 20, max 50
-- Returns the signed-in BA's own shelf pictures, newest first.
-- NO image bytes here - the app loads each picture from
--   GET shelf-picture/image/:id   (see 2_shelf_picture_image_GET.sql)
--
-- ASSUMED COLUMN NAMES (check with the query at the bottom of this file):
--   HRMS.BA_SALES_SHELF_PICTURES.PICTURE_ID  <- primary key
--   HRMS.BA_SALES_LOCATIONS.MART_NAME
-- =====================================================================
DECLARE
    l_auth_header  VARCHAR2(4000);
    l_token        VARCHAR2(4000);
    l_token_hash   VARCHAR2(512);
    l_user_id      NUMBER;
    l_page         PLS_INTEGER;
    l_size         PLS_INTEGER;
    l_offset       PLS_INTEGER;
    l_total        NUMBER;
    l_has_more     BOOLEAN;
    l_started      BOOLEAN := FALSE;

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
    -- PAGING
    --------------------------------------------------

    l_page := GREATEST(NVL(:page, 1), 1);
    l_size := LEAST(GREATEST(NVL(:page_size, 20), 1), 50);
    l_offset := (l_page - 1) * l_size;

    SELECT COUNT(*)
      INTO l_total
      FROM HRMS.BA_SALES_SHELF_PICTURES
     WHERE USER_ID = l_user_id;

    l_has_more := (l_offset + l_size) < l_total;

    --------------------------------------------------
    -- RESPONSE
    --------------------------------------------------

    :status_code := 200;

    OWA_UTIL.MIME_HEADER('application/json', FALSE);
    HTP.P('Cache-Control: no-store');
    OWA_UTIL.HTTP_HEADER_CLOSE;
    l_started := TRUE;

    APEX_JSON.OPEN_OBJECT;
    APEX_JSON.WRITE('success',   TRUE);
    APEX_JSON.WRITE('total',     l_total);
    APEX_JSON.WRITE('page',      l_page);
    APEX_JSON.WRITE('page_size', l_size);
    APEX_JSON.WRITE('has_more',  l_has_more);
    APEX_JSON.OPEN_ARRAY('pictures');

    FOR r IN (
        SELECT p.PICTURE_ID,
               p.PICTURE_TYPE,
               p.FILE_NAME,
               p.REMARKS,
               p.LOCATION_ID,
               loc.MART_NAME,
               p.LATITUDE,
               p.LONGITUDE,
               p.ATTENDANCE_ID,
               TO_CHAR(NVL(p.CAPTURED_AT, p.CREATED_AT),
                       'YYYY-MM-DD"T"HH24:MI:SS') AS CAPTURED_TXT
          FROM HRMS.BA_SALES_SHELF_PICTURES p
          LEFT JOIN HRMS.BA_SALES_LOCATIONS loc
            ON loc.LOCATION_ID = p.LOCATION_ID
         WHERE p.USER_ID = l_user_id
         ORDER BY NVL(p.CAPTURED_AT, p.CREATED_AT) DESC, p.PICTURE_ID DESC
        OFFSET l_offset ROWS FETCH NEXT l_size ROWS ONLY
    ) LOOP
        APEX_JSON.OPEN_OBJECT;
        APEX_JSON.WRITE('picture_id',    r.PICTURE_ID);
        APEX_JSON.WRITE('captured_at',   r.CAPTURED_TXT);
        APEX_JSON.WRITE('picture_type',  r.PICTURE_TYPE);
        APEX_JSON.WRITE('file_name',     r.FILE_NAME);
        APEX_JSON.WRITE('remarks',       r.REMARKS);
        APEX_JSON.WRITE('location_id',   r.LOCATION_ID);
        APEX_JSON.WRITE('location_name', r.MART_NAME);
        APEX_JSON.WRITE('latitude',      r.LATITUDE);
        APEX_JSON.WRITE('longitude',     r.LONGITUDE);
        APEX_JSON.WRITE('attendance_id', r.ATTENDANCE_ID);
        APEX_JSON.CLOSE_OBJECT;
    END LOOP;

    APEX_JSON.CLOSE_ARRAY;
    APEX_JSON.CLOSE_OBJECT;

EXCEPTION
    WHEN OTHERS THEN
        IF NOT l_started THEN
            send_error(500, 'Unable to load shelf pictures. Check the ORDS error log for details.');
        END IF;
END;

-- ---------------------------------------------------------------------
-- Run once to confirm the column names used above:
--   SELECT column_name, data_type
--     FROM all_tab_columns
--    WHERE owner = 'HRMS' AND table_name = 'BA_SALES_SHELF_PICTURES';
--   SELECT column_name FROM all_tab_columns
--    WHERE owner = 'HRMS' AND table_name = 'BA_SALES_LOCATIONS';
-- If the primary key is not PICTURE_ID (e.g. SHELF_PICTURE_ID), replace
-- PICTURE_ID in this file and in file 2.
-- ---------------------------------------------------------------------
