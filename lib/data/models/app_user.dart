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

/// A signed-in user for the local demo session.
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
}
