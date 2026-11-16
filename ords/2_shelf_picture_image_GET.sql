-- =====================================================================
-- ORDS handler : GET  shelf-picture/image/:id   (module ba_sales_v2)
-- Source type  : PL/SQL        (:id is the URI template parameter)
-- Streams one shelf picture (BLOB). Only the owner BA can read it.
-- =====================================================================
DECLARE
    l_auth_header  VARCHAR2(4000);
    l_token        VARCHAR2(4000);
    l_token_hash   VARCHAR2(512);
    l_user_id      NUMBER;
    l_blob         BLOB;
    l_mime         VARCHAR2(100);
    l_len          NUMBER;

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
    -- LOAD THE PICTURE (must belong to this BA)
    --------------------------------------------------

    BEGIN
        SELECT SHELF_IMAGE,
               IMAGE_MIME_TYPE
          INTO l_blob,
               l_mime
          FROM HRMS.BA_SALES_SHELF_PICTURES
         WHERE PICTURE_ID = :id
           AND USER_ID    = l_user_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            send_error(404, 'Picture not found.');
            RETURN;
    END;

    l_len := NVL(DBMS_LOB.GETLENGTH(l_blob), 0);

    IF l_len = 0 THEN
        send_error(404, 'Picture is empty.');
        RETURN;
    END IF;

    IF LOWER(NVL(l_mime, 'image/jpeg')) NOT IN ('image/jpeg', 'image/png') THEN
        l_mime := 'image/jpeg';
    END IF;

    :status_code := 200;

    OWA_UTIL.MIME_HEADER(LOWER(l_mime), FALSE);
    HTP.P('Content-Length: ' || TO_CHAR(l_len));
    HTP.P('Cache-Control: private, max-age=86400');
    OWA_UTIL.HTTP_HEADER_CLOSE;

    WPG_DOCLOAD.DOWNLOAD_FILE(l_blob);

EXCEPTION
    WHEN OTHERS THEN
        send_error(500, 'Unable to load the picture. Check the ORDS error log for details.');
END;
