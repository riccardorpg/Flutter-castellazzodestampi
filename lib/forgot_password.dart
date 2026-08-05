import 'package:flutter/material.dart';
import 'services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Inserisci il tuo indirizzo email.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.forgotPassword(email);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      setState(() => _sent = true);
    } else {
      setState(
        () => _error = result['message'] as String? ?? 'Errore. Riprova.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Color(0xFF111111),
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(child: _sent ? _buildSuccess() : _buildForm()),
    );
  }

  Widget _buildForm() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = (constraints.maxWidth * 0.24).clamp(88.0, 120.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            // -0.45 = leggermente sopra il centro verticale
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        width: boxSize,
                        height: boxSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDF5E9),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.lock_reset,
                          color: const Color(0xFF7BA566),
                          size: boxSize * 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'Password dimenticata?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF111111),
                          fontSize: 22,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: Text(
                        'Inserisci la tua email. Ti invieremo\nuna password temporanea.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'EMAIL',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InputField(
                      controller: _emailController,
                      hintText: 'La tua email',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7BA566),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFF7BA566,
                          ).withValues(alpha: 0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'INVIA',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Inter',
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccess() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = (constraints.maxWidth * 0.26).clamp(96.0, 128.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: const Alignment(0, -0.45),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: boxSize,
                      height: boxSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF5E9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.mark_email_read_outlined,
                        color: const Color(0xFF7BA566),
                        size: boxSize * 0.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Email inviata!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 22,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Controlla la tua casella di posta.\nUsa la password temporanea per accedere,\npoi cambiala dalle impostazioni.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 14,
                        fontFamily: 'Inter',
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7BA566),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'TORNA AL LOGIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          color: Color(0xFF111111),
          fontSize: 15,
          fontFamily: 'Inter',
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
