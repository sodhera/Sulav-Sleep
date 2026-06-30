import {
  Montserrat_400Regular,
  Montserrat_500Medium,
  Montserrat_600SemiBold,
  Montserrat_700Bold,
  Montserrat_800ExtraBold,
  useFonts,
} from '@expo-google-fonts/montserrat';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import Svg, { Path, Rect } from 'react-native-svg';
import {
  ActiveSession,
  C,
  loadActive,
  loadProfile,
  loadSessions,
  Profile,
  resetAll,
  S,
  saveActive,
  saveProfile,
  saveSessions,
  scoreFor,
  seedSessions,
  Session,
  T,
  windowMinutes,
} from './src/core';
import { Home } from './src/Home';
import { Onboarding } from './src/Onboarding';
import { Reports } from './src/Reports';

type Tab = 'home' | 'reports';

function HomeIcon({ active }: { active: boolean }) {
  const c = active ? C.white : C.faint;
  return (
    <Svg width={24} height={24} viewBox="0 0 24 24">
      <Path d="M3 11 L12 3.5 L21 11" stroke={c} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <Path d="M5.5 9.5 L5.5 20 L18.5 20 L18.5 9.5" stroke={c} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  );
}

function ChartIcon({ active }: { active: boolean }) {
  const c = active ? C.white : C.faint;
  return (
    <Svg width={24} height={24} viewBox="0 0 24 24">
      <Rect x="4" y="12" width="3.4" height="8" rx="1.5" fill={c} />
      <Rect x="10.3" y="7" width="3.4" height="13" rx="1.5" fill={c} />
      <Rect x="16.6" y="9.5" width="3.4" height="10.5" rx="1.5" fill={c} />
    </Svg>
  );
}

function BottomNav({ tab, onTab }: { tab: Tab; onTab: (t: Tab) => void }) {
  const items: { id: Tab; label: string; Icon: typeof HomeIcon }[] = [
    { id: 'home', label: 'Home', Icon: HomeIcon },
    { id: 'reports', label: 'Reports', Icon: ChartIcon },
  ];
  return (
    <View style={{ position: 'absolute', left: 0, right: 0, bottom: 0 }}>
      <LinearGradient colors={['transparent', 'rgba(15,9,38,0.92)']} style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 120 }} pointerEvents="none" />
      <SafeAreaView edges={['bottom']}>
        <View style={{ flexDirection: 'row', justifyContent: 'center', gap: S.huge, paddingTop: S.md, paddingBottom: S.sm }}>
          {items.map(({ id, label, Icon }) => {
            const on = tab === id;
            return (
              <Pressable key={id} onPress={() => onTab(id)} style={{ alignItems: 'center', gap: 4, paddingHorizontal: S.lg, paddingVertical: S.xs }}>
                <Icon active={on} />
                <Text style={{ color: on ? C.white : C.faint, fontFamily: on ? T.semibold : T.medium, fontSize: 11 }}>{label}</Text>
              </Pressable>
            );
          })}
        </View>
      </SafeAreaView>
    </View>
  );
}

export default function App() {
  const [fontsLoaded, fontError] = useFonts({
    Montserrat_400Regular,
    Montserrat_500Medium,
    Montserrat_600SemiBold,
    Montserrat_700Bold,
    Montserrat_800ExtraBold,
  });

  const [ready, setReady] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [active, setActive] = useState<ActiveSession>(null);
  const [tab, setTab] = useState<Tab>('home');

  useEffect(() => {
    (async () => {
      const [p, s, a] = await Promise.all([loadProfile(), loadSessions(), loadActive()]);
      setProfile(p);
      setSessions(s);
      setActive(a);
      setReady(true);
    })();
  }, []);

  if ((!fontsLoaded && !fontError) || !ready) {
    return <View style={{ flex: 1, backgroundColor: C.bgBottom }} />;
  }

  // ── Onboarding gate ──────────────────────────────────────────────────────
  if (!profile?.onboarded) {
    return (
      <SafeAreaProvider>
        <StatusBar style="light" />
        <Onboarding
          onDone={async (data) => {
            const next: Profile = { ...data, onboarded: true };
            const seeded = seedSessions(windowMinutes(next.bedtime, next.wakeTime), Date.now());
            await saveProfile(next);
            await saveSessions(seeded);
            setProfile(next);
            setSessions(seeded);
          }}
        />
      </SafeAreaProvider>
    );
  }

  // ── Handlers ─────────────────────────────────────────────────────────────
  const sleepNow = async () => {
    const a = { startISO: new Date().toISOString() };
    await saveActive(a);
    setActive(a);
  };

  const wake = async () => {
    if (!active) return;
    const durationMin = Math.max(1, Math.round((Date.now() - new Date(active.startISO).getTime()) / 60000));
    const target = windowMinutes(profile.bedtime, profile.wakeTime);
    const s: Session = {
      id: `s-${Date.now()}`,
      startISO: active.startISO,
      endISO: new Date().toISOString(),
      durationMin,
      score: scoreFor(durationMin, target),
    };
    const nextSessions = [...sessions, s];
    await saveSessions(nextSessions);
    await saveActive(null);
    setSessions(nextSessions);
    setActive(null);
  };

  const saveSchedule = async (bed: number, wakeT: number) => {
    const next = { ...profile, bedtime: bed, wakeTime: wakeT };
    await saveProfile(next);
    setProfile(next);
  };

  const saveName = async (name: string) => {
    const next = { ...profile, name };
    await saveProfile(next);
    setProfile(next);
  };

  const reset = async () => {
    await resetAll();
    setProfile(null);
    setSessions([]);
    setActive(null);
    setTab('home');
  };

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      <View style={{ flex: 1, backgroundColor: C.bgBottom }}>
        {tab === 'home' ? (
          <Home
            profile={profile}
            sessions={sessions}
            active={active}
            onSleepNow={sleepNow}
            onWake={wake}
            onSaveSchedule={saveSchedule}
            onSaveName={saveName}
            onReset={reset}
          />
        ) : (
          <Reports sessions={sessions} />
        )}
        {!active && <BottomNav tab={tab} onTab={setTab} />}
      </View>
    </SafeAreaProvider>
  );
}
