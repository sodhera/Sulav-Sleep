import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

/*
 * Sulav Sleep — "Dusk" design system
 * --------------------------------------------------------------------------
 * Identity: the last warm light at the horizon bleeding up into deep night.
 * A cool deep-plum sky meets a warm clay/peach horizon glow with a soft moon
 * resting low. Cosiness comes from warmth at the edges, airy light numerals,
 * an editorial serif voice, and a strict 8pt spatial rhythm.
 * See DESIGN.md for the full rationale.
 */

// ── Spatial rhythm — strict 8pt grid (Apple HIG) ─────────────────────────────
const S = { xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32, huge: 40 };

// ── Radii ────────────────────────────────────────────────────────────────────
const R = { sm: 14, md: 18, lg: 24, xl: 32, pill: 999 };

// ── Palette: warm dusk ───────────────────────────────────────────────────────
const C = {
  // base
  bg0: '#15111B',     // deep plum-black
  bg1: '#1B1622',
  // ink (warm off-whites, never sharp white)
  cream: '#F4E9DC',
  warm: '#C9B3A0',
  quiet: '#8E7C70',
  faint: 'rgba(244,233,220,0.34)',
  // dusk accents
  clay: '#D98E6E',
  peach: '#E9B488',
  gold: '#E6C089',
  // surfaces
  card: '#221A29',
  cardHi: '#2A2230',
  line: '#322839',
  lineSoft: '#271F2E',
  // moon + sky
  moon: '#F7EAD7',
};

// ── Type: an editorial serif voice (Hoefler Text) over a humanist UI sans.
//    The serif carries warmth + personality; the sans keeps controls legible. ─
const T = {
  serif: 'Hoefler Text',
  serifItalic: 'Hoefler Text',
  sans: 'Avenir Next',
};

function haptic() {
  Haptics.selectionAsync().catch(() => {});
}

// 14 stars, only across the dark upper sky so they read. [x%, y%, size, opacity]
const STARS: [number, number, number, number][] = [
  [10, 9, 1.6, 0.7], [24, 6, 1.1, 0.5], [38, 12, 2.0, 0.85], [52, 7, 1.2, 0.55],
  [66, 13, 1.5, 0.6], [81, 8, 1.4, 0.6], [91, 18, 1.1, 0.45], [16, 20, 1.2, 0.5],
  [44, 24, 1.5, 0.55], [72, 28, 1.0, 0.4], [33, 32, 1.3, 0.5], [60, 34, 1.1, 0.42],
  [86, 30, 1.2, 0.45], [6, 27, 1.0, 0.4],
];

// ── The dusk widget — the emotional centre of the app ────────────────────────
function DuskWidget({
  duration,
  score,
  quality,
  week,
}: {
  duration: string;
  score: number;
  quality: string;
  week: number[];
}) {
  const DAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  return (
    <View
      style={{
        height: 392,
        borderRadius: R.xl,
        borderCurve: 'continuous',
        overflow: 'hidden',
        borderWidth: 1,
        borderColor: C.lineSoft,
      }}
    >
      {/* Sky: deep plum at the top warming to clay at the horizon */}
      <LinearGradient
        colors={['#221A30', '#352741', '#5A3F4E', '#92604F', '#C9885F']}
        locations={[0, 0.34, 0.56, 0.74, 0.92]}
        start={{ x: 0.3, y: 0 }}
        end={{ x: 0.7, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />

      {/* Stars in the dark upper sky */}
      {STARS.map(([x, y, s, o], i) => (
        <View
          key={i}
          style={{
            position: 'absolute',
            left: `${x}%`,
            top: `${y}%`,
            width: s,
            height: s,
            borderRadius: s / 2,
            backgroundColor: C.moon,
            opacity: o,
          }}
        />
      ))}

      {/* Moon — soft warm disc resting low, wrapped in graduated glow */}
      <View style={{ position: 'absolute', top: 96, left: '54%', marginLeft: -104, width: 208, height: 208, borderRadius: 104, backgroundColor: 'rgba(233,180,136,0.045)' }} />
      <View style={{ position: 'absolute', top: 112, left: '54%', marginLeft: -88, width: 176, height: 176, borderRadius: 88, backgroundColor: 'rgba(238,196,156,0.05)' }} />
      <View style={{ position: 'absolute', top: 128, left: '54%', marginLeft: -72, width: 144, height: 144, borderRadius: 72, backgroundColor: 'rgba(243,209,176,0.06)' }} />
      <View style={{ position: 'absolute', top: 142, left: '54%', marginLeft: -58, width: 116, height: 116, borderRadius: 58, backgroundColor: 'rgba(247,224,198,0.08)' }} />
      <View style={{ position: 'absolute', top: 154, left: '54%', marginLeft: -46, width: 92, height: 92, borderRadius: 46, backgroundColor: 'rgba(249,236,218,0.14)' }} />
      <View style={{ position: 'absolute', top: 164, left: '54%', marginLeft: -38, width: 76, height: 76, borderRadius: 38, backgroundColor: C.moon, opacity: 0.97 }} />

      {/* A single soft distant ridge, kept restrained */}
      <View style={{ position: 'absolute', bottom: -120, left: -40, width: 260, height: 260, borderRadius: 130, backgroundColor: '#7A4E45', opacity: 0.5 }} />
      <View style={{ position: 'absolute', bottom: -140, right: -50, width: 300, height: 300, borderRadius: 150, backgroundColor: '#6B4540', opacity: 0.55 }} />

      {/* Ground haze settling the scene */}
      <LinearGradient
        colors={['transparent', 'rgba(21,17,27,0.55)', '#15111B']}
        locations={[0, 0.6, 1]}
        start={{ x: 0, y: 0 }}
        end={{ x: 0, y: 1 }}
        style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 150 }}
        pointerEvents="none"
      />

      {/* Overlay content */}
      <View style={{ flex: 1, padding: S.xxl, justifyContent: 'space-between' }}>
        {/* Greeting */}
        <Text style={{ color: C.faint, fontFamily: T.sans, fontSize: 13, fontWeight: '600', letterSpacing: 0.5 }}>
          Last night
        </Text>

        {/* Metric block at the base */}
        <View style={{ gap: S.lg }}>
          <View style={{ flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between' }}>
            <View style={{ gap: S.xs }}>
              <Text style={{ color: C.cream, fontFamily: T.serif, fontSize: 52, lineHeight: 56, fontWeight: '500' }}>
                {duration}
              </Text>
              <Text style={{ color: C.warm, fontFamily: T.serifItalic, fontSize: 17, fontStyle: 'italic' }}>
                {quality}
              </Text>
            </View>

            {/* Score badge */}
            <View style={{ alignItems: 'center', gap: 3, paddingBottom: S.xs }}>
              <Text style={{ color: C.peach, fontFamily: T.serif, fontSize: 34, fontWeight: '600', fontVariant: ['tabular-nums'] }}>
                {score}
              </Text>
              <Text style={{ color: C.faint, fontFamily: T.sans, fontSize: 11, fontWeight: '700', letterSpacing: 1 }}>
                SCORE
              </Text>
            </View>
          </View>

          {/* Seven-night rhythm */}
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end' }}>
            {week.map((v, i) => {
              const today = i === week.length - 1;
              const h = 14 + Math.round((v / 100) * 28);
              return (
                <View key={i} style={{ alignItems: 'center', gap: S.sm }}>
                  <View
                    style={{
                      width: 5,
                      height: h,
                      borderRadius: 3,
                      backgroundColor: today ? C.peach : `rgba(244,233,220,${v >= 80 ? 0.42 : 0.24})`,
                    }}
                  />
                  <Text
                    style={{
                      color: today ? C.peach : C.faint,
                      fontFamily: T.sans,
                      fontSize: 10,
                      fontWeight: today ? '800' : '600',
                    }}
                  >
                    {DAYS[i]}
                  </Text>
                </View>
              );
            })}
          </View>
        </View>
      </View>
    </View>
  );
}

// ── Primary action — warm, glowing, the commitment ──────────────────────────
function PrimaryAction({ label, sub, onPress }: { label: string; sub: string; onPress?: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={() => {
        haptic();
        onPress?.();
      }}
      style={({ pressed }) => ({
        borderRadius: R.lg,
        borderCurve: 'continuous',
        overflow: 'hidden',
        opacity: pressed ? 0.9 : 1,
        transform: [{ scale: pressed ? 0.99 : 1 }],
      })}
    >
      <LinearGradient
        colors={['#ECBB8C', '#DD9870']}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={{ minHeight: 64, paddingHorizontal: S.xxl, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}
      >
        <View style={{ gap: 2 }}>
          <Text style={{ color: '#2A1A12', fontFamily: T.sans, fontSize: 17, fontWeight: '800' }}>{label}</Text>
          <Text style={{ color: 'rgba(42,26,18,0.6)', fontFamily: T.sans, fontSize: 13, fontWeight: '600' }}>{sub}</Text>
        </View>
        <View style={{ width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(42,26,18,0.14)' }}>
          <Text style={{ color: '#2A1A12', fontSize: 18, marginTop: -1 }}>☾</Text>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

// ── Secondary action — quiet surface, value on the right ────────────────────
function SecondaryAction({ label, value, onPress }: { label: string; value: string; onPress?: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={() => {
        haptic();
        onPress?.();
      }}
      style={({ pressed }) => ({
        minHeight: 64,
        borderRadius: R.lg,
        borderCurve: 'continuous',
        backgroundColor: C.card,
        borderWidth: 1,
        borderColor: C.line,
        paddingHorizontal: S.xxl,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        opacity: pressed ? 0.85 : 1,
      })}
    >
      <Text style={{ color: C.cream, fontFamily: T.sans, fontSize: 17, fontWeight: '700' }}>{label}</Text>
      <Text style={{ color: C.peach, fontFamily: T.sans, fontSize: 16, fontWeight: '700', fontVariant: ['tabular-nums'] }}>{value}</Text>
    </Pressable>
  );
}

// ── A small cozy stat ────────────────────────────────────────────────────────
function StatCard({ value, label }: { value: string; label: string }) {
  return (
    <View
      style={{
        flex: 1,
        backgroundColor: C.card,
        borderRadius: R.md,
        borderCurve: 'continuous',
        borderWidth: 1,
        borderColor: C.lineSoft,
        padding: S.lg,
        gap: S.xs,
      }}
    >
      <Text style={{ color: C.cream, fontFamily: T.serif, fontSize: 22, fontWeight: '600', fontVariant: ['tabular-nums'] }}>{value}</Text>
      <Text style={{ color: C.quiet, fontFamily: T.sans, fontSize: 12, fontWeight: '600' }}>{label}</Text>
    </View>
  );
}

// ── Settings row ─────────────────────────────────────────────────────────────
function SettingRow({ label, value, last }: { label: string; value: string; last?: boolean }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={haptic}
      style={({ pressed }) => ({
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        minHeight: 52,
        paddingHorizontal: S.xl,
        borderBottomWidth: last ? 0 : StyleSheet.hairlineWidth,
        borderBottomColor: C.line,
        opacity: pressed ? 0.6 : 1,
      })}
    >
      <Text style={{ color: C.warm, fontFamily: T.sans, fontSize: 15, fontWeight: '600' }}>{label}</Text>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: S.sm }}>
        <Text style={{ color: C.quiet, fontFamily: T.sans, fontSize: 15, fontWeight: '600' }}>{value}</Text>
        <Text style={{ color: C.quiet, fontFamily: T.sans, fontSize: 18, fontWeight: '300' }}>›</Text>
      </View>
    </Pressable>
  );
}

// ── App ──────────────────────────────────────────────────────────────────────
export default function App() {
  const [bedtime] = useState('10:30 PM');
  const week = [76, 82, 69, 91, 78, 84, 88];

  return (
    <SafeAreaProvider>
      <LinearGradient colors={[C.bg0, C.bg1, C.bg0]} locations={[0, 0.5, 1]} style={{ flex: 1 }}>
        <StatusBar style="light" />
        <SafeAreaView edges={['top', 'bottom']} style={{ flex: 1 }}>
          <ScrollView
            contentInsetAdjustmentBehavior="never"
            showsVerticalScrollIndicator={false}
            contentContainerStyle={{ paddingHorizontal: S.xxl, paddingTop: S.sm, paddingBottom: S.huge, gap: S.xxxl }}
          >
            {/* Header */}
            <View style={{ flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between', paddingTop: S.sm }}>
              <View style={{ gap: S.xs }}>
                <Text style={{ color: C.cream, fontFamily: T.serif, fontSize: 28, fontWeight: '500' }}>Good evening</Text>
                <Text style={{ color: C.quiet, fontFamily: T.sans, fontSize: 14, fontWeight: '500' }}>Sunday, June 30</Text>
              </View>
              <View
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 22,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: C.card,
                  borderWidth: 1,
                  borderColor: C.line,
                }}
              >
                <Text style={{ color: C.peach, fontSize: 18 }}>☾</Text>
              </View>
            </View>

            {/* The dusk widget */}
            <DuskWidget duration="7h 24m" score={88} quality="Restful and unbroken" week={week} />

            {/* Actions */}
            <View style={{ gap: S.md }}>
              <PrimaryAction label="Sleep Now" sub="Quiet the phone until 6:30 AM" />
              <SecondaryAction label="Set Bedtime" value={bedtime} />
            </View>

            {/* Cozy stats */}
            <View style={{ flexDirection: 'row', gap: S.md }}>
              <StatCard value="10:42" label="Avg. bedtime" />
              <StatCard value="5 nights" label="On-time streak" />
            </View>

            {/* Settings */}
            <View style={{ gap: S.md }}>
              <Text style={{ color: C.warm, fontFamily: T.serif, fontSize: 19, fontWeight: '600', paddingHorizontal: S.xs }}>
                Settings
              </Text>
              <View
                style={{
                  backgroundColor: C.card,
                  borderRadius: R.lg,
                  borderCurve: 'continuous',
                  borderWidth: 1,
                  borderColor: C.lineSoft,
                  overflow: 'hidden',
                }}
              >
                <SettingRow label="Lock duration" value="6 hours" />
                <SettingRow label="Wind-down reminder" value="1 hr before" />
                <SettingRow label="Morning unlock" value="6:30 AM" />
                <SettingRow label="Allowed apps" value="4" last />
              </View>
            </View>
          </ScrollView>
        </SafeAreaView>
      </LinearGradient>
    </SafeAreaProvider>
  );
}
