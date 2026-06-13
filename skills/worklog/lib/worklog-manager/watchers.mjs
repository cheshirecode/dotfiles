import path from "node:path";

export const WATCHER_VALIDATION_SCHEMA_VERSION = "worklog.watcher-validation.v1";

function samePath(left, right) {
  return path.resolve(left) === path.resolve(right);
}

function pushDuplicatePath(errors, configs, field) {
  for (let i = 0; i < configs.length; i += 1) {
    for (let j = i + 1; j < configs.length; j += 1) {
      if (samePath(configs[i][field], configs[j][field])) {
        errors.push({
          code: `${field}.duplicate`,
          message: `Watcher configs '${configs[i].instance}' and '${configs[j].instance}' share ${field}.`,
          instances: [configs[i].instance, configs[j].instance],
        });
      }
    }
  }
}

export function validateWatcherConfigs(configs) {
  const errors = [];
  const warnings = [];
  pushDuplicatePath(errors, configs, "stateDir");
  pushDuplicatePath(errors, configs, "cacheDir");

  for (const config of configs) {
    if (!config.poll.enabled) continue;
    if (!config.poll.issueUrls.length) {
      errors.push({
        code: "poll.issue_urls_missing",
        message: `Watcher config '${config.instance}' is enabled but has no poll.issueUrls.`,
        instances: [config.instance],
      });
    }
  }

  const targets = new Map();
  for (const config of configs.filter((item) => item.poll.enabled)) {
    for (const issueUrl of config.poll.issueUrls) {
      const key = String(issueUrl || "").trim();
      if (!key) continue;
      const prior = targets.get(key) || [];
      for (const other of prior) {
        if (other.marker === config.daemon.statusCommentMarker) {
          errors.push({
            code: "poll.status_marker_collision",
            message: `Enabled watcher configs '${other.instance}' and '${config.instance}' target the same issue with the same status marker.`,
            issueUrl: key,
            instances: [other.instance, config.instance],
          });
        } else {
          warnings.push({
            code: "poll.issue_url_shared",
            message: `Enabled watcher configs '${other.instance}' and '${config.instance}' target the same issue; markers differ, but command ownership should be intentional.`,
            issueUrl: key,
            instances: [other.instance, config.instance],
          });
        }
      }
      prior.push({ instance: config.instance, marker: config.daemon.statusCommentMarker });
      targets.set(key, prior);
    }
  }

  return {
    schemaVersion: WATCHER_VALIDATION_SCHEMA_VERSION,
    configCount: configs.length,
    errors,
    warnings,
    ok: errors.length === 0,
  };
}
