import { runDailyRefresh } from './refresh.js';
import { logger } from '../utils/logger.js';

const IST_OFFSET_MIN = 330;

/** Next occurrence of `hour:00` India time strictly after `now`. */
export function nextRunAt(hourIST, now = new Date()) {
  const istNow = new Date(now.getTime() + IST_OFFSET_MIN * 60000);
  const candidate = Date.UTC(istNow.getUTCFullYear(), istNow.getUTCMonth(), istNow.getUTCDate(), hourIST, 0, 0) - IST_OFFSET_MIN * 60000;
  return new Date(candidate > now.getTime() ? candidate : candidate + 86400000);
}

/** In-process daily scheduler (no extra dependency). Returns a stop() function. */
export function startDailyRefresh({ hourIST = 3, onStartup = false, run = runDailyRefresh } = {}) {
  let timer;
  let stopped = false;
  const schedule = () => {
    if (stopped) return;
    const at = nextRunAt(hourIST);
    logger.info('Next opportunity refresh scheduled', { at: at.toISOString() });
    timer = setTimeout(async () => {
      await run({ trigger: 'schedule' });
      schedule();
    }, at.getTime() - Date.now());
    timer.unref?.();
  };
  schedule();
  if (onStartup) run({ trigger: 'startup' }).catch((e) => logger.error('Startup refresh failed', { error: e }));
  return () => { stopped = true; clearTimeout(timer); };
}
