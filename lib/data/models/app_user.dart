/// The four roles available in the InstituteOS demo.
enum AppRole { owner, counselor, trainer, accounts }

extension AppRoleLabel on AppRole {
  String get label => switch (this) {
    AppRole.owner => 'Owner / Admin',
    AppRole.counselor => 'Counselor',
    AppRole.trainer => 'Trainer',
    AppRole.accounts => 'Accounts Staff',
  };
}

extension AppRoleValue on AppRole {
  String get value => switch (this) {
    AppRole.owner => 'owner',
    AppRole.counselor => 'counselor',
    AppRole.trainer => 'trainer',
    AppRole.accounts => 'accounts',
  };
}

/// A signed-in user for the InstituteOS workspace.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final AppRole role;

  static AppRole? roleFromString(String? value) =>
      switch ((value ?? '').trim().toLowerCase()) {
        'owner' => AppRole.owner,
        'counselor' => AppRole.counselor,
        'trainer' => AppRole.trainer,
        'accounts' || 'accounts staff' => AppRole.accounts,
        _ => null,
      };
}
