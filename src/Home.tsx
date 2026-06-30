import { useEffect, useRef, useState } from 'react';
import { Animated, Pressable, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Background } from './Background';
import {
  ActiveSession,
  C,
  fmtClock,
  fmtDuration,
  Profile,
  S,
  Session,
  T,
  windowMinutes,
} from './core';
import { ScheduleModal, SettingsModal } from './modals';
import { GhostButton, PrimaryButton } from './ui';

function Gear({ onPress }: { onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      hitSlop={10}
      style={{ width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', backgroundColor: C.glass, borderWidth: 1, borderColor: C.hair }}
    >
      <Text style={{ color: C.dim, fontSize: 17 }}>☾</Text>
    </Pressable>
  );
}

export function Home({
  profile,
  sessions,
  active,
  onSleepNow,
  onWake,
  onSaveSchedule,
  onSaveName,
  onReset,
}: {
  profile: Profile;
  sessions: Session[];
  active: ActiveSession;
  onSleepNow: () => void;
  onWake: () => void;
  onSaveSchedule: (bed: number, wake: number) => void;
  onSaveName: (name: string) => void;
  onReset: () => void;
}) {
  const scrollY = useRef(new Animated.Value(0)).current;
  const [showSchedule, setShowSchedule] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);

  const last = sessions[sessions.length - 1];
  const targetMin = windowMinutes(profile.bedtime, profile.wakeTime);
  const today = new Date();
  const dateLabel = today.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });

  // streak: consecutive most-recent nights with score >= 80
  let streak = 0;
  for (let i = sessions.length - 1; i >= 0; i--) {
    if (sessions[i].score >= 80) streak++;
    else break;
  }

  const elapsedMin = active ? (now - new Date(active.startISO).getTime()) / 60000 : 0;

  return (
    <View style={{ flex: 1 }}>
      <Background scrollY={scrollY} />

      <SafeAreaView style={{ flex: 1 }} edges={['top']}>
        <Animated.ScrollView
          showsVerticalScrollIndicator={false}
          scrollEventThrottle={16}
          onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
          contentContainerStyle={{ paddingHorizontal: S.xxl, paddingTop: S.sm, paddingBottom: 140 }}
        >
          {/* Header */}
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', minHeight: 44 }}>
            <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14 }}>{dateLabel}</Text>
            <Gear onPress={() => setShowSettings(true)} />
          </View>

          {active ? (
            // ── Sleeping state ──────────────────────────────────────────────
            <View style={{ alignItems: 'center', paddingTop: S.huge * 2.4, gap: S.sm }}>
              <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 15 }}>Good night, {profile.name}</Text>
              <Text style={{ color: C.white, fontFamily: T.extra, fontSize: 56, marginTop: S.lg }}>
                {Math.floor(elapsedMin / 60)}h {String(Math.floor(elapsedMin % 60)).padStart(2, '0')}m
              </Text>
              <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14 }}>
                Sleeping since {fmtClock(new Date(active.startISO).getHours() * 60 + new Date(active.startISO).getMinutes())}
              </Text>
              <Text style={{ color: C.faint, fontFamily: T.medium, fontSize: 13, marginTop: S.sm, textAlign: 'center', maxWidth: 260 }}>
                The phone is resting. Wake up when you're ready and we'll log your night.
              </Text>
              <View style={{ height: S.huge * 2.2 }} />
              <View style={{ alignSelf: 'stretch' }}>
                <PrimaryButton label="Wake up" onPress={onWake} />
              </View>
            </View>
          ) : (
            // ── Awake / planning state ─────────────────────────────────────
            <>
              <View style={{ paddingTop: S.huge * 1.4, alignItems: 'center', gap: S.xs }}>
                <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 16 }}>Good evening,</Text>
                <Text style={{ color: C.white, fontFamily: T.extra, fontSize: 34 }}>{profile.name}</Text>
              </View>

              {/* Tonight schedule — open text, no card */}
              <View style={{ alignItems: 'center', gap: 2, paddingTop: S.huge * 1.1 }}>
                <Text style={{ color: C.faint, fontFamily: T.semibold, fontSize: 12, letterSpacing: 1 }}>TONIGHT</Text>
                <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 22 }}>
                  {fmtClock(profile.bedtime)}  →  {fmtClock(profile.wakeTime)}
                </Text>
                <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>{fmtDuration(targetMin)} in bed</Text>
              </View>

              {/* Actions */}
              <View style={{ gap: S.md, paddingTop: S.huge * 1.2 }}>
                <PrimaryButton label="Sleep Now" onPress={onSleepNow} />
                <GhostButton label="Set Bedtime" value={fmtClock(profile.bedtime)} onPress={() => setShowSchedule(true)} />
              </View>

              {/* Last night — open summary, hairline divider only */}
              <View style={{ paddingTop: S.huge * 1.3, gap: S.lg }}>
                <View style={{ height: 1, backgroundColor: C.hair }} />
                {last ? (
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end' }}>
                    <View style={{ gap: 2 }}>
                      <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>Last night</Text>
                      <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 28 }}>{fmtDuration(last.durationMin)}</Text>
                    </View>
                    <View style={{ alignItems: 'flex-end', gap: 2 }}>
                      <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>Score</Text>
                      <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 28 }}>{last.score}</Text>
                    </View>
                  </View>
                ) : (
                  <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14 }}>
                    No nights logged yet. Tap Sleep Now when you head to bed.
                  </Text>
                )}
                {streak > 0 && (
                  <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 14 }}>
                    🌙  {streak} night{streak > 1 ? 's' : ''} on track
                  </Text>
                )}
              </View>
            </>
          )}
        </Animated.ScrollView>
      </SafeAreaView>

      {showSchedule && (
        <ScheduleModal
          bedtime={profile.bedtime}
          wakeTime={profile.wakeTime}
          onClose={() => setShowSchedule(false)}
          onSave={(b, w) => {
            onSaveSchedule(b, w);
            setShowSchedule(false);
          }}
        />
      )}

      {showSettings && (
        <SettingsModal
          profile={profile}
          onClose={() => setShowSettings(false)}
          onSaveName={onSaveName}
          onOpenSchedule={() => {
            setShowSettings(false);
            setShowSchedule(true);
          }}
          onReset={() => {
            setShowSettings(false);
            onReset();
          }}
        />
      )}
    </View>
  );
}
