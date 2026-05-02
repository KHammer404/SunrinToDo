String? safeRedirectPath(String? value) {
  if (value == null || value.isEmpty) return null;
  if (!value.startsWith('/') || value.startsWith('//')) return null;
  if (value == '/auth' || value == '/domain-error') return null;
  return value;
}
