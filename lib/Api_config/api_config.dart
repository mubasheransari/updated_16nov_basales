/// Central place for every endpoint used by the BA module.
class ApiConfig {
  static const String base = 'http://tapex.mezangrp.com/ords/hrms/ba-sales-v2';

  static const String locations = '$base/locations/list/';
  static const String signup = '$base/auth/signup/';
  static const String checkBaCnic = '$base/auth/check-ba-cnic/';
  static const String login = '$base/auth/login/';
  static const String profile = '$base/auth/profile/';
  static const String attendanceIn = '$base/auth/attendance-in/';
  static const String attendanceOut = '$base/auth/attendance-out/';
  static const String skuList = '$base/sku/list/';

  /// NOTE: no trailing slash here - matches your curl exactly.
  static const String enterSales = '$base/enter_sales';

  /// Shelf picture upload (JSON + base64 image). No trailing slash, same as
  /// the sample. Uses the same host as every other BA API.
  static const String shelfUpload = '$base/shelf-picture/upload';

  /// Authenticated list of the signed-in BA's shelf pictures
  /// Returns all shelf-picture metadata for the signed-in BA; no image bytes.
  static const String shelfList = '$base/shelf-picture/list/';

  /// Raw image of one shelf picture (needs the Bearer token header).
  static String shelfImage(int pictureId) =>
      '$base/shelf-picture/image/$pictureId';

  /// Low stock submit (BA ticks SKUs that are running low).
  static const String lowStockSubmit = '$base/low-stock/submit';

  /// Customer review questions (ticked per product on the low stock screen).
  static const String reviewQuestions = '$base/review/questions';

  /// Asks the server whether an account may be used on this phone.
  static const String deviceCheck = '$base/auth/device/check';

  /// Links an account to this phone (right after sign up, or after login).
  static const String deviceBind = '$base/auth/device/bind';

  /// New device reassignment flow.
  static const String deviceIdCheck = '$base/auth/device-id/check/';
  static const String deviceIdUpdate = '$base/auth/device-id/update/';

  /// Home dashboard chart: GET ?period=7d|2w|1m|1y
  static const String dashboardSales = '$base/dashboard/sales';

  /// Complaints / problems: title + description + optional picture.
  /// (The chat / reply / status endpoints are not available on the Oracle
  /// side yet, so the app only creates and lists complaints.)
  static const String complaintCreate = '$base/complaint/create';
  static const String complaintList = '$base/complaint/list';

  /// Leave self-service endpoints (no chat / message endpoints for now).
  static const String leaveApply = '$base/leave/apply';
  static const String leaveList = '$base/leave/list';
  static String leaveCancel(int id) => '$base/leave/cancel/$id';

  static const Duration timeout = Duration(seconds: 30);

  /// Uploading a photo is slower than a normal call.
  static const Duration uploadTimeout = Duration(seconds: 90);
}
//mock locations 
//shlef picture upload
//