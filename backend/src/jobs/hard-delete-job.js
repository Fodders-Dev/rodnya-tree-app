// Phase 3.6 hard-delete background job.
//
// Sweeps physically deleted entries past their retention window
// (soft-delete → hard-delete). Storage is document-based (single JSON
// blob via FileStore либо PostgresStore single-row JSONB), so the
// actual cleanup logic lives в `store.hardDeleteExpired` — это файл
// thin wrapper:
//
//   * `runHardDeleteJob({store, config, runtimeInfo})` — один cycle
//     (timeout-guarded, logging, error capture). Re-usable из
//     scheduler либо из tests / manual triggers.
//   * `scheduleHardDeleteJob({store, config, runtimeInfo})` —
//     setInterval-based scheduler с lastRunAt-aware catch-up на
//     startup (backend restarts чаще interval'а не должны skip'ать
//     runs entirely). Returns `{stop}` для tests / shutdown.
//
// Rollout (DECISIONS.md 2026-05-18):
//   1. Deploy с RODNYA_HARD_DELETE_ENABLED=false (default) → job
//      не register'ится, log «hard-delete-job disabled».
//   2. Flip enabled=true → restart → 60s после startup первый run
//      (firstRunDry=true default → dry, log counts + sample ids).
//   3. Артёмов review log → flip RODNYA_HARD_DELETE_FIRST_RUN_DRY=false
//      → next 24h cycle live.

const crypto = require("node:crypto");

const HOUR_MS = 3_600_000;
const FIRST_RUN_DELAY_MS = 60_000;
const MIN_INTERVAL_MS = 60_000;

function logEvent(level, event, payload) {
  const target = level === "error" ? console.error : level === "warn" ? console.warn : console.log;
  target(`[backend] ${event}`, JSON.stringify({event, ...payload}));
}

async function runHardDeleteJob({store, config, runtimeInfo, override = {}} = {}) {
  const startedAt = new Date();
  const runId = override.runId || crypto.randomUUID();

  if (config.hardDeletePaused && !override.ignorePause) {
    logEvent("log", "hard_delete_run", {
      runId,
      startedAt: startedAt.toISOString(),
      paused: true,
      reason: "RODNYA_HARD_DELETE_PAUSED",
    });
    return {paused: true, runId, startedAt: startedAt.toISOString()};
  }

  // Effective dry-run: explicit override > firstRunDry > dryRun env.
  // firstRunDry интенсивно gates ALL runs до того как Артём flip'нет
  // env var (per DECISIONS.md 2026-05-18 rollout sequence).
  const effectiveDryRun = Boolean(
    override.dryRun ??
      config.hardDeleteFirstRunDry ??
      config.hardDeleteDryRun ??
      false,
  );

  try {
    const summary = await store.hardDeleteExpired({
      now: startedAt,
      retentionDays: Number(config.hardDeleteRetentionDays) || 30,
      auditRetentionDays: Number(config.hardDeleteAuditRetentionDays) || 90,
      maxPerRun: Number(config.hardDeleteMaxPerRun) || 10_000,
      dryRun: effectiveDryRun,
      runId,
    });
    logEvent("log", "hard_delete_run", {
      ...summary,
      paused: false,
      firstRunDry: Boolean(config.hardDeleteFirstRunDry),
      errors: [],
    });
    return summary;
  } catch (error) {
    const message = error?.message || String(error);
    const stack = error?.stack || null;
    if (runtimeInfo && typeof runtimeInfo.captureError === "function") {
      runtimeInfo.captureError("hard_delete_job", error, {runId});
    }
    logEvent("error", "hard_delete_run", {
      runId,
      startedAt: startedAt.toISOString(),
      finishedAt: new Date().toISOString(),
      paused: false,
      firstRunDry: Boolean(config.hardDeleteFirstRunDry),
      errors: [message],
      stack,
    });
    return {error: message, runId, startedAt: startedAt.toISOString()};
  }
}

async function computeFirstDelayMs({store, config}) {
  // firstRunDry overrides → run через 60s чтобы Артём не ждал
  // полный 24h interval ради dry log review.
  if (config.hardDeleteFirstRunDry) {
    return FIRST_RUN_DELAY_MS;
  }

  const intervalMs = Math.max(
    MIN_INTERVAL_MS,
    Number(config.hardDeleteIntervalHours || 24) * HOUR_MS,
  );

  let lastRunIso = null;
  try {
    const db = await store._read();
    lastRunIso =
      db && typeof db.hardDeleteLastRunAt === "string"
        ? db.hardDeleteLastRunAt
        : null;
  } catch (error) {
    logEvent("warn", "hard_delete_schedule_init_warning", {
      message: error?.message || String(error),
    });
    return FIRST_RUN_DELAY_MS;
  }

  if (!lastRunIso) {
    return FIRST_RUN_DELAY_MS;
  }
  const elapsed = Date.now() - Date.parse(lastRunIso);
  if (!Number.isFinite(elapsed) || elapsed >= intervalMs) {
    return FIRST_RUN_DELAY_MS;
  }
  return Math.max(FIRST_RUN_DELAY_MS, intervalMs - elapsed);
}

function scheduleHardDeleteJob({store, config, runtimeInfo} = {}) {
  if (!config || !config.hardDeleteEnabled) {
    logEvent("log", "hard_delete_job_disabled", {
      reason: "RODNYA_HARD_DELETE_ENABLED is not true",
    });
    return null;
  }

  const intervalMs = Math.max(
    MIN_INTERVAL_MS,
    Number(config.hardDeleteIntervalHours || 24) * HOUR_MS,
  );

  let intervalHandle = null;
  let firstTimeout = null;
  let stopped = false;

  const bootstrap = (async () => {
    const firstDelay = await computeFirstDelayMs({store, config});
    if (stopped) return;
    logEvent("log", "hard_delete_job_scheduled", {
      firstRunInMs: firstDelay,
      intervalMs,
      retentionDays: Number(config.hardDeleteRetentionDays) || 30,
      auditRetentionDays: Number(config.hardDeleteAuditRetentionDays) || 90,
      maxPerRun: Number(config.hardDeleteMaxPerRun) || 10_000,
      firstRunDry: Boolean(config.hardDeleteFirstRunDry),
      dryRun: Boolean(config.hardDeleteDryRun),
      paused: Boolean(config.hardDeletePaused),
    });

    firstTimeout = setTimeout(async () => {
      if (stopped) return;
      await runHardDeleteJob({store, config, runtimeInfo}).catch((error) => {
        if (runtimeInfo && typeof runtimeInfo.captureError === "function") {
          runtimeInfo.captureError("hard_delete_job_bootstrap", error);
        }
      });
      if (stopped) return;
      intervalHandle = setInterval(() => {
        runHardDeleteJob({store, config, runtimeInfo}).catch((error) => {
          if (runtimeInfo && typeof runtimeInfo.captureError === "function") {
            runtimeInfo.captureError("hard_delete_job_interval", error);
          }
        });
      }, intervalMs);
      // Tests / graceful shutdown: don't keep event loop alive purely
      // for this timer.
      if (typeof intervalHandle.unref === "function") {
        intervalHandle.unref();
      }
    }, firstDelay);
    if (typeof firstTimeout.unref === "function") {
      firstTimeout.unref();
    }
  })();

  return {
    bootstrap, // for tests / startup ordering
    stop() {
      stopped = true;
      if (firstTimeout) clearTimeout(firstTimeout);
      if (intervalHandle) clearInterval(intervalHandle);
      firstTimeout = null;
      intervalHandle = null;
    },
  };
}

module.exports = {
  runHardDeleteJob,
  scheduleHardDeleteJob,
  computeFirstDelayMs,
  FIRST_RUN_DELAY_MS,
  MIN_INTERVAL_MS,
};
