/**
 * Calendar-day difference in India Standard Time, so "closes in N days"
 * matches what students see on a calendar (and in the iOS app).
 */
const IST_OFFSET_MS = 5.5 * 3600000;
const DAY = 86400000;
const istDayNumber = (d) => Math.floor((new Date(d).getTime() + IST_OFFSET_MS) / DAY);

export function calendarDaysUntil(date, now = new Date()) {
  return istDayNumber(date) - istDayNumber(now);
}
