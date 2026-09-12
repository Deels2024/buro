const moderationSections = new Set(["items", "claims", "matches", "moderation", "support"]);
const administrationSections = new Set([
  ...moderationSections, "overview", "organizations", "users", "integrations", "analytics", "settings",
]);

export function canAccessSection(role: string, section: string): boolean {
  if (role === "admin") return administrationSections.has(section);
  return role === "moderator" && moderationSections.has(section);
}
