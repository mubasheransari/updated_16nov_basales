import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ords_ba/Data/device_id.dart';
import 'package:ords_ba/Repository/repository.dart';
import 'package:ords_ba/Theme/app_theme.dart';
import 'package:ords_ba/Widgets/common.dart';

/// Three-field device reassignment sheet. It is only opened when the BA taps
/// "Update Device ID" (login screen / profile) and can be closed any time.
/// CNIC is checked with the same allowlist endpoint used by BA registration.
Future<bool> showDeviceUpdateSheet(
  BuildContext context, {
  required Repository repository,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeviceUpdateSheet(repository: repository),
  );
  return result == true;
}

class _DeviceUpdateSheet extends StatefulWidget {
  const _DeviceUpdateSheet({required this.repository});
  final Repository repository;

  @override
  State<_DeviceUpdateSheet> createState() => _DeviceUpdateSheetState();
}

class _DeviceUpdateSheetState extends State<_DeviceUpdateSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cnic = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _cnicVerified = false;

  @override
  void dispose() {
    _name.dispose();
    _cnic.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _cnicVerified = false;
    });
    try {
      // Reuse the existing registration CNIC allowlist API.
      final verification = await widget.repository.checkBaCnic(
        cnic: _cnic.text,
      );
      if (!verification.allowed) {
        throw ApiException(verification.message);
      }
      final registeredName = verification.fullName?.trim();
      if (registeredName == null || registeredName.isEmpty) {
        throw const ApiException(
          'CNIC was found, but the registered name was not returned. Contact IT Support.',
        );
      }
      if (registeredName.toLowerCase() != _name.text.trim().toLowerCase()) {
        throw const ApiException(
          'Full name does not match the name registered against this CNIC.',
        );
      }

      setState(() => _cnicVerified = true);

      // API 2 must perform its own CNIC/account validation server-side.
      final message = await widget.repository.updateDeviceId(
        fullName: _name.text.trim(),
        cnic: _cnic.text,
        deviceId: DeviceId.value,
      );
      if (!mounted) return;
      showToast(context, message, error: false);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to update device. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        child: SafeArea(
          top: false,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Icon(Icons.phonelink_setup_rounded,
                          color: AppColors.red, size: 26),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Update Device ID',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.textDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Changed your phone or want to link this phone to your BA account? Verify your details to update the Device ID.',
                    style: TextStyle(color: AppColors.textDim, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('Full Name'),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Enter your registered full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Full name is required.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('CNIC'),
                  TextFormField(
                    controller: _cnic,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(13),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Enter 13-digit CNIC',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (v) => (v == null ||
                            v.replaceAll(RegExp(r'\D'), '').length != 13)
                        ? 'Enter a valid 13-digit CNIC.'
                        : null,
                    onChanged: (_) {
                      if (_cnicVerified || _error != null) {
                        setState(() {
                          _cnicVerified = false;
                          _error = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Device ID'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F3F6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E5EA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.smartphone_rounded,
                            color: AppColors.textDim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            DeviceId.value,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(Icons.lock_outline_rounded,
                            color: AppColors.textDim, size: 18),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      text: 'VERIFY & UPDATE DEVICE',
                      icon: Icons.verified_user_rounded,
                      loading: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'CNIC is verified against your existing BA registration.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textDim, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
}
