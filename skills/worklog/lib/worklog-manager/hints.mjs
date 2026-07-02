export function refusalHint(code) {
  switch (code) {
    case "command.missing":
      return "Use a supported command word such as ask, plan, do, agent, dry-run, or add Worklog-Command: ask.";
    case "slug.missing":
      return "Mention a unique worklog slug or add Worklog-Slug: <slug>.";
    case "slug.ambiguous":
      return "Mention exactly one worklog slug or add Worklog-Slug: <slug>.";
    case "slug.default_not_found":
      return "Update daemon.defaultSlug to a slug present in this worklog instance.";
    case "slug.not_found":
      return "Use a slug that exists in this worklog instance.";
    case "command.ambiguous":
      return "Use exactly one intent, or add Worklog-Command: ask|plan|do|agent.";
    case "command.invalid":
      return "Use Worklog-Command: ask, plan, do, or agent.";
    case "command.not_allowed":
      return "Use a command enabled in this watcher instance.";
    case "identity.mismatch":
      return "Use the configured trusted GitHub login for this watcher.";
    case "repo.not_allowed":
      return "Use an issue in this instance's configured GitHub allowlist.";
    case "issue.drift":
      return "Refresh the issue and rerun from the current title/body hash.";
    case "execution.disabled":
      return "Enable daemon.execution before requesting sandbox execution.";
    case "execution.command_not_allowed":
      return "Use a command enabled for sandbox execution.";
    case "execution.confirmation_missing":
      return "Explicitly request the configured sandbox execution confirmation before --execute can run.";
    case "execution.invalid_target":
      return "Use Worklog-Execute: sandbox.";
    default:
      return "Inspect the local run artifact and adjust the issue/comment to satisfy the reported gate.";
  }
}

export function refusalHints(codes) {
  const hints = [];
  const seen = new Set();
  for (const code of codes) {
    const hint = refusalHint(code);
    if (seen.has(hint)) continue;
    seen.add(hint);
    hints.push(hint);
  }
  return hints;
}
