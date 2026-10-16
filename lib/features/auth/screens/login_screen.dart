import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../controllers/session_controller.dart';
import '../services/mock_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.sessionController, super.key});

  final SessionController sessionController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillDemoAccount(DemoAccount account) {
    _emailController.text = account.user.email;
    _passwordController.text = account.password;
    widget.sessionController.clearError();
    setState(() {});
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.sessionController.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 880;
    final isCompact = width < 480;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isCompact ? 20 : 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _loginCard(context)),
                        const SizedBox(width: 28),
                        SizedBox(width: 360, child: _demoAccountsCard(context)),
                      ],
                    )
                  : Column(
                      children: [
                        _loginCard(context),
                        const SizedBox(height: 20),
                        _demoAccountsCard(context),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginCard(BuildContext context) {
    final session = widget.sessionController;
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BrandHeader(),
              const SizedBox(height: 30),
              if (session.errorMessage != null) ...[
                _ErrorMessage(message: session.errorMessage!),
                const SizedBox(height: 18),
              ],
              Text(
                'Sign in to your workspace',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Use a demo account to explore role-specific views.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Colors.blueGrey.shade600),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                enabled: !session.isLoading,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your email address.';
                  }
                  if (!value.contains('@')) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                enabled: !session.isLoading,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: session.isLoading
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter your password.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: session.isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: session.isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Log in'),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'This is a local demo. It does not use secure production authentication.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.blueGrey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _demoAccountsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _DemoModeBadge(),
            const SizedBox(height: 16),
            Text(
              'Explore each workspace',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: AppTheme.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose an account to fill its credentials.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.blueGrey.shade600),
            ),
            const SizedBox(height: 14),
            ...MockAuthService.demoAccounts.map(
              (account) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DemoAccountTile(
                  account: account,
                  onTap: () => _fillDemoAccount(account),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: AppTheme.brand,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'InstituteOS',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink),
            ),
            Text(
              'AI-Powered Institute Operations',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.blueGrey.shade600),
            ),
          ],
        ),
      ],
    );
  }
}

class _DemoModeBadge extends StatelessWidget {
  const _DemoModeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: 15, color: AppTheme.brand),
          SizedBox(width: 6),
          Text(
            'DEMO MODE',
            style: TextStyle(
              color: AppTheme.brand,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoAccountTile extends StatelessWidget {
  const _DemoAccountTile({required this.account, required this.onTap});

  final DemoAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE8F0FF),
                child: Text(
                  account.user.name.substring(0, 1),
                  style: const TextStyle(
                    color: AppTheme.brand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.user.role.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.user.email,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Password: ${account.password}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8A1C13)),
            ),
          ),
        ],
      ),
    );
  }
}
