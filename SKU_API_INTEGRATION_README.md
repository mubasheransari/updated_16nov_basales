# BA Sales Flutter App — SKU API Integration

## Product API used by Enter Sales

GET `http://tapex.mezangrp.com/ords/hrms/ba-sales-v2/sku/list/`

The endpoint is configured in `lib/Api_config/api_config.dart` as `ApiConfig.skuList`.

## Where it is used

- `lib/Screens/products.dart` (`ProductsScreen`) loads products when the Enter Sales screen opens and when the refresh button / pull-to-refresh is used.
- `lib/Repository/repository.dart` (`fetchSkus`) calls the endpoint, filters inactive rows, and maps the response to `Sku` objects.
- `lib/Model/models.dart` (`Sku.fromJson`) maps these API fields:
  - `sku_id` → product identifier
  - `item_code` → product code
  - `item_name` → product name
  - `con_blend_name` → blend name
  - `sku_group` → category/group
  - `active` → active status
- Product quantities are added to the cart and submitted through the existing `enter_sales` endpoint. The SKU ID from the product API is used in the sale payload.

## Expected ORDS response

For a Collection Feed, the response should include an `items` array. Each row should expose the fields above (ORDS commonly returns unquoted column names in lowercase). Pagination links are supported.

Example row:
```json
{
  "sku_id": 1,
  "item_code": "SKU001",
  "item_name": "Example product",
  "con_blend_name": "Example blend",
  "sku_group": "Example brand",
  "active": "Y"
}
```

## Run

1. Extract this ZIP.
2. Open the `ba_sales_26oct` folder in Android Studio or VS Code.
3. Run `flutter pub get`.
4. Run `flutter run`.

## Important

- The API host currently uses HTTP, so Android cleartext traffic is enabled in `android/app/src/main/AndroidManifest.xml`.
- I could not run `flutter analyze` or build an APK in this environment because the Flutter SDK is not installed here.
- The Oracle ORDS endpoint must be published and reachable from the device. The endpoint should return the expected field names and active product rows.
