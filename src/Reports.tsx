import { useRef } from 'react';
import { Animated, Text, useWindowDimensions, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Background } from './Background';
import { C, fmtDuration, S, Session, T } from './core';
import { WeeklyChart } from './ui';

function dayLabel(iso: string) {
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

export function Reports({ sessions }: { sessions: Session[] }) {
  const scrollY = useRef(new Animated.Value(0)).current;
  const { width } = useWindowDimensions();
  const chartW = width - S.xxl * 2;

  const last7 = sessions.slice(-7);
  const hours = last7.map((s) => s.durationMin / 60);
  const dayLetters = last7.map((s) => new Date(s.endISO).toLocaleDateString(undefined, { weekday: 'narrow' }));

  const avgDur = sessions.length ? Math.round(sessions.reduce((a, s) => a + s.durationMin, 0) / sessions.length) : 0;
  const avgScore = sessions.length ? Math.round(sessions.reduce((a, s) => a + s.score, 0) / sessions.length) : 0;
  const ordered = [...sessions].reverse();

  return (
    <View style={{ flex: 1 }}>
      <Background scrollY={scrollY} />
      <SafeAreaView style={{ flex: 1 }} edges={['top']}>
        <Animated.ScrollView
          showsVerticalScrollIndicator={false}
          scrollEventThrottle={16}
          onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
          contentContainerStyle={{ paddingHorizontal: S.xxl, paddingTop: S.lg, paddingBottom: 140 }}
        >
          <Text style={{ color: C.white, fontFamily: T.extra, fontSize: 30, paddingTop: S.sm }}>Reports</Text>

          {sessions.length === 0 ? (
            <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 15, paddingTop: S.huge }}>
              Your nights will appear here once you start logging sleep.
            </Text>
          ) : (
            <>
              {/* Weekly chart — cardless */}
              <View style={{ paddingTop: S.xxl, gap: S.sm }}>
                <Text style={{ color: C.faint, fontFamily: T.semibold, fontSize: 12, letterSpacing: 1 }}>LAST 7 NIGHTS</Text>
                <WeeklyChart width={chartW} hours={hours} />
                <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                  {dayLetters.map((d, i) => (
                    <Text key={i} style={{ color: i === dayLetters.length - 1 ? C.white : C.faint, fontFamily: T.medium, fontSize: 11 }}>
                      {d}
                    </Text>
                  ))}
                </View>
              </View>

              {/* Averages — open text */}
              <View style={{ flexDirection: 'row', paddingTop: S.huge, gap: S.huge }}>
                <View style={{ gap: 2 }}>
                  <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>Avg. duration</Text>
                  <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 26 }}>{fmtDuration(avgDur)}</Text>
                </View>
                <View style={{ gap: 2 }}>
                  <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>Avg. score</Text>
                  <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 26 }}>{avgScore}</Text>
                </View>
              </View>

              {/* History — clean rows, hairline dividers, no cards */}
              <View style={{ paddingTop: S.huge, gap: 0 }}>
                <Text style={{ color: C.faint, fontFamily: T.semibold, fontSize: 12, letterSpacing: 1, marginBottom: S.md }}>HISTORY</Text>
                {ordered.map((s, i) => (
                  <View
                    key={s.id}
                    style={{
                      flexDirection: 'row',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      paddingVertical: S.lg,
                      borderTopWidth: i === 0 ? 0 : 1,
                      borderTopColor: C.hair,
                    }}
                  >
                    <View style={{ gap: 3 }}>
                      <Text style={{ color: C.white, fontFamily: T.semibold, fontSize: 15 }}>{dayLabel(s.endISO)}</Text>
                      <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>{fmtDuration(s.durationMin)}</Text>
                    </View>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: S.md }}>
                      <View style={{ width: 70, height: 4, borderRadius: 2, backgroundColor: C.hair, overflow: 'hidden' }}>
                        <View style={{ width: `${s.score}%`, height: '100%', backgroundColor: C.white }} />
                      </View>
                      <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 17, width: 30, textAlign: 'right' }}>{s.score}</Text>
                    </View>
                  </View>
                ))}
              </View>
            </>
          )}
        </Animated.ScrollView>
      </SafeAreaView>
    </View>
  );
}
