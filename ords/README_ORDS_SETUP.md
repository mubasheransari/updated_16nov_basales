# ORDS setup for this update

All three go in the existing module **ba_sales_v2** (base path `ba-sales-v2`).

## 1. Shelf picture list  (fixes the 404 on Shelf Images)
- Template: `shelf-picture/list`  | Method: GET | Source type: PL/SQL
- Source: `1_shelf_picture_list_GET.sql`
- Add 2 parameters (Source = URI / query string): `page` (INTEGER) and `page_size` (INTEGER), bind variables with the same names.

## 2. Shelf picture image
- Template: `shelf-picture/image/:id` | Method: GET | Source type: PL/SQL
- Source: `2_shelf_picture_image_GET.sql`
- Test: `curl -H "Authorization: Bearer <token>" http://tapex.mezangrp.com/ords/hrms/ba-sales-v2/shelf-picture/image/<id> --output t.jpg`

Before publishing 1 and 2, run the two `all_tab_columns` queries at the bottom
of file 1. If the shelf table's primary key is not `PICTURE_ID`, or the mart
name column is not `MART_NAME`, change those names in both files.

## 3. Low stock submit  (replace the old POST handler for `low-stock/submit`)
- Source: `3_low_stock_submit_POST.sql` (Option A, calls your `low_stock_submit`).
- If it still fails inside that procedure, set `c_debug` to TRUE temporarily to
  see the Oracle error in the app, or use `4_low_stock_submit_STANDALONE_POST.sql`
  (Option B, own tables, run its DDL first).

Request the app now sends (same idea as enter_sales - no user_id):
```json
{"location_id": 12, "stock_date": "2026-11-13",
 "items": [{"sku_id": 101, "question_ids": [1, 3]}]}
```
