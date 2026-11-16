# Optional Shelf Pictures — ORDS setup

This Flutter update expects the following behavior:

- Attendance IN still requires the attendance selfie and GPS. It does not require a shelf picture.
- Attendance OUT still requires the attendance selfie and GPS. It does not require a shelf picture.
- While checked in, the BA can tap the camera icon on the Attendance map screen to capture/upload a shelf picture at any time.
- The Home screen has no Shelf Pictures card. No image preview, gallery, or picture-history screen is included in this phase; picture viewing can be added later.
- Sales unlock after attendance IN; shelf uploads do not control sales access.

## 1. Attendance IN

Leave the supplied Attendance IN handler unchanged. It already validates and stores only the attendance selfie. Do not add a shelf-picture validation to it.

## 2. Attendance OUT

In the supplied Attendance OUT handler:

1. Remove the mandatory shelf validation block:

```sql
IF NVL(DBMS_LOB.GETLENGTH(l_shelf_b64), 0) = 0 THEN
    respond(400, '{"success":false,"message":"A shelf picture is required."}');
    RETURN;
END IF;
```

2. Keep the selfie mandatory validation.
3. Replace the unconditional shelf decode + insert with the following conditional block. It uses the same shelf columns as your existing handler:

```sql
-- Shelf picture is optional at attendance OUT.
IF NVL(DBMS_LOB.GETLENGTH(l_shelf_b64), 0) > 0 THEN
    l_step := 'decode shelf picture';
    l_shelf := HRMS.BA_B64_TO_BLOB(l_shelf_b64);

    IF HRMS.BA_VALID_IMAGE(l_shelf) = 0 THEN
        ROLLBACK;
        respond(400, '{"success":false,"message":"The shelf picture is not a valid image."}');
        RETURN;
    END IF;

    l_step := 'insert shelf picture';
    INSERT INTO HRMS.BA_SALES_SHELF_PICTURES (
        USER_ID, LOCATION_ID, LATITUDE, LONGITUDE, CAPTURED_AT,
        IMAGE_MIME_TYPE, SHELF_IMAGE, REMARKS, FILE_NAME, CREATED_AT,
        PICTURE_TYPE, ATTENDANCE_ID
    ) VALUES (
        l_user_id, l_location_id, l_lat, l_lng, SYSTIMESTAMP,
        l_shelf_mime, l_shelf, l_shelf_remarks,
        'shelf_out_' || TO_CHAR(l_attendance_id) || '.jpg',
        SYSTIMESTAMP, 'OUT', l_attendance_id
    );
END IF;
```

Do not remove the OUT selfie insert, attendance update, or final COMMIT.

## 3. Secure the existing shelf-picture upload handler

The supplied upload handler trusts `user_id` from the request body and does not validate the Bearer token. Before production, update it so the signed-in session determines the BA identity. Add these declarations:

```sql
l_auth       VARCHAR2(4000);
l_token      VARCHAR2(4000);
l_token_hash VARCHAR2(512);
l_role       VARCHAR2(20);
l_assigned_location_id NUMBER;
```

Before parsing the JSON body, validate the token and load the BA identity:

```sql
l_auth := OWA_UTIL.GET_CGI_ENV('HTTP_AUTHORIZATION');
IF l_auth IS NULL THEN
  l_auth := OWA_UTIL.GET_CGI_ENV('Authorization');
END IF;

IF l_auth IS NULL OR NOT REGEXP_LIKE(l_auth, '^Bearer +[^ ]+$', 'i') THEN
  :status_code := 401;
  OWA_UTIL.MIME_HEADER('application/json', TRUE);
  HTP.P('{"status":"error","message":"Bearer token is required."}');
  RETURN;
END IF;

l_token := TRIM(REGEXP_REPLACE(l_auth, '^Bearer +', '', 1, 1, 'i'));
l_token_hash := APEX_UTIL.GET_HASH(
  APEX_T_VARCHAR2('BA_SALES_SESSION_V1', l_token), FALSE
);

BEGIN
  SELECT u.USER_ID, u.ROLE_CODE, u.LOCATION_ID
    INTO l_user_id, l_role, l_assigned_location_id
    FROM HRMS.BA_SALES_SESSIONS s
    JOIN HRMS.BA_SALES_USERS u ON u.USER_ID = s.USER_ID
   WHERE s.TOKEN_HASH = l_token_hash
     AND s.REVOKED_AT IS NULL
     AND s.EXPIRES_AT > SYSTIMESTAMP
     AND u.STATUS = 'ACTIVE';
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    :status_code := 401;
    OWA_UTIL.MIME_HEADER('application/json', TRUE);
    HTP.P('{"status":"error","message":"Invalid or expired session."}');
    RETURN;
  WHEN TOO_MANY_ROWS THEN
    :status_code := 401;
    OWA_UTIL.MIME_HEADER('application/json', TRUE);
    HTP.P('{"status":"error","message":"Invalid session."}');
    RETURN;
END;

IF l_role <> 'BA' THEN
  :status_code := 403;
  OWA_UTIL.MIME_HEADER('application/json', TRUE);
  HTP.P('{"status":"error","message":"Only BA users can upload shelf pictures."}');
  RETURN;
END IF;
```

After parsing the JSON, do not assign `l_user_id` from `APEX_JSON.GET_NUMBER('user_id')`. Ignore/remove that body field. Validate the submitted location against the authenticated user's assigned location:

```sql
IF l_loc_id IS NULL OR l_assigned_location_id IS NULL
   OR l_loc_id <> l_assigned_location_id THEN
  :status_code := 403;
  OWA_UTIL.MIME_HEADER('application/json', TRUE);
  HTP.P('{"status":"error","message":"This location is not assigned to your account."}');
  RETURN;
END IF;
```

The Flutter client can continue sending `user_id` for compatibility, but the server must ignore it and use the authenticated `l_user_id`.

## 4. Picture listing (Shelf Images screen)

The app now has a **Shelf Images** card on the Home screen. It needs two GET
handlers in module `ba_sales_v2` (code in the `ords/` folder):

- `shelf-picture/list`      -> `ords/1_shelf_picture_list_GET.sql`
- `shelf-picture/image/:id` -> `ords/2_shelf_picture_image_GET.sql`

See `ords/README_ORDS_SETUP.md` for the exact template / parameter setup.
