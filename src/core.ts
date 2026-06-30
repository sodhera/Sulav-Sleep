import AsyncStorage from '@react-native-async-storage/async-storage';

/*
 * core — theme tokens, time helpers, persistence, and sleep scoring.
 * Kept in one module so the rest of the app stays declarative.
 */

// ── Theme ────────────────────────────────────────────────────────────────────
export const S = { xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32, huge: 40 };
export const R = { sm: 14, md: 18, lg: 22, xl: 28, pill: 999 };

export const C = {
  bgTop: '#2A1C66',
  bgMid: '#241858',
  bgBottom: '#170F36',
  indigo: '#291965',
  purple: '#533EA8',
  magenta: '#943EC3',
  white: '#FFFFFF',
  dim: 'rgba(255,255,255,0.74)',
  quiet: 'rgba(255,255,255,0.52)',
  faint: 'rgba(255,255,255,0.30)',
  hair: 'rgba(255,255,255,0.10)',
  glass: 'rgba(255,255,255,0.06)',
  moon: '#F4F1FF',
};

export const T = {
  regular: 'Montserrat_400Regular',
  medium: 'Montserrat_500Medium',
  semibold: 'Montserrat_600SemiBold',
  bold: 'Montserrat_700Bold',
  extra: 'Montserrat_800ExtraBold',
};

// ── Time helpers (time-of-day as minutes from midnight) ──────────────────────
export function fmtClock(minutes: number) {
  const m = ((minutes % 1440) + 1440) % 1440;
  let h = Math.floor(m / 60);
  const min = m % 60;
  const period = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h === 0) h = 12;
  return `${h}:${String(min).padStart(2, '0')} ${period}`;
}

export function fmtDuration(mins: number) {
  const h = Math.floor(mins / 60);
  const m = Math.round(mins % 60);
  return `${h}h ${String(m).padStart(2, '0')}m`;
}

// Window length in minutes, wrapping past midnight (bed 22:30 → wake 06:30).
export function windowMinutes(bed: number, wake: number) {
  let diff = wake - bed;
  if (diff <= 0) diff += 1440;
  return diff;
}

// ── Types ────────────────────────────────────────────────────────────────────
export type Profile = {
  name: string;
  bedtime: number; // minutes from midnight
  wakeTime: number;
  onboarded: boolean;
};

export type Session = {
  id: string;
  startISO: string;
  endISO: string;
  durationMin: number;
  score: number;
};

export type ActiveSession = { startISO: string } | null;

// ── Scoring ──────────────────────────────────────────────────────────────────
// Reward hitting (or beating) the target window; penalise being well short.
export function scoreFor(durationMin: number, targetMin: number) {
  const ratio = durationMin / Math.max(targetMin, 1);
  let score: number;
  if (ratio >= 1) score = 92 + Math.min(8, (ratio - 1) * 30); // slight bonus, capped
  else score = 100 - (1 - ratio) * 140; // fall off as you undersleep
  return Math.max(40, Math.min(100, Math.round(score)));
}

// ── Persistence ──────────────────────────────────────────────────────────────
const K_PROFILE = 'sulav.profile.v1';
const K_SESSIONS = 'sulav.sessions.v1';
const K_ACTIVE = 'sulav.active.v1';

export async function loadProfile(): Promise<Profile | null> {
  const raw = await AsyncStorage.getItem(K_PROFILE);
  return raw ? (JSON.parse(raw) as Profile) : null;
}
export async function saveProfile(p: Profile) {
  await AsyncStorage.setItem(K_PROFILE, JSON.stringify(p));
}

export async function loadSessions(): Promise<Session[]> {
  const raw = await AsyncStorage.getItem(K_SESSIONS);
  return raw ? (JSON.parse(raw) as Session[]) : [];
}
export async function saveSessions(list: Session[]) {
  await AsyncStorage.setItem(K_SESSIONS, JSON.stringify(list));
}

export async function loadActive(): Promise<ActiveSession> {
  const raw = await AsyncStorage.getItem(K_ACTIVE);
  return raw ? (JSON.parse(raw) as ActiveSession) : null;
}
export async function saveActive(a: ActiveSession) {
  if (a) await AsyncStorage.setItem(K_ACTIVE, JSON.stringify(a));
  else await AsyncStorage.removeItem(K_ACTIVE);
}

export async function resetAll() {
  await AsyncStorage.multiRemove([K_PROFILE, K_SESSIONS, K_ACTIVE]);
}

// Seed a handful of plausible recent nights so Reports/charts feel alive on day one.
export function seedSessions(targetMin: number, now: number): Session[] {
  const samples = [430, 468, 384, 502, 410, 451]; // minutes slept, oldest → newest
  return samples.map((dur, i) => {
    const daysAgo = samples.length - i;
    const end = now - daysAgo * 86400000 + 7 * 3600000;
    const start = end - dur * 60000;
    return {
      id: `seed-${i}`,
      startISO: new Date(start).toISOString(),
      endISO: new Date(end).toISOString(),
      durationMin: dur,
      score: scoreFor(dur, targetMin),
    };
  });
}
