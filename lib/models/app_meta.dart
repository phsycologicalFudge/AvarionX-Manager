class AppMeta {
  final String name;
  final String description;
  final String iconPath;
  final String heroImagePath;
  final List<String> screenshots;
  final String repo;
  final String package;
  final bool archived;

  const AppMeta({
    required this.name,
    required this.description,
    required this.iconPath,
    required this.heroImagePath,
    required this.screenshots,
    required this.repo,
    required this.package,
    required this.archived,
  });
}