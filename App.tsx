import {
  Montserrat_400Regular,
  Montserrat_500Medium,
  Montserrat_600SemiBold,
  Montserrat_700Bold,
  Montserrat_800ExtraBold,
  useFonts,
} from '@expo-google-fonts/montserrat';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { Pressable, ScrollView, Text, useWindowDimensions, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import Svg, {
  Circle,
  Defs,
  Ellipse,
  G,
  LinearGradient as SvgGradient,
  Mask,
  Path,
  Rect,
  Stop,
} from 'react-native-svg';

/*
 * Sulav Sleep — purple "Lullaby" system
 * --------------------------------------------------------------------------
 * Direction taken straight from the reference: a deep indigo night sky,
 * a soft crescent moon nestled in clouds, friendly Montserrat type, and
 * dreamy violet→magenta accents. Rounded, calm, a little magical.
 * Palette anchors: #291965 / #533EA8 / #943EC3. See DESIGN.md.
 */

const S = { xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32, huge: 40 };
const R = { sm: 14, md: 18, lg: 22, xl: 28, pill: 999 };

const C = {
  bgTop: '#2A1C66',
  bgBottom: '#191038',
  indigo: '#291965',
  purple: '#533EA8',
  magenta: '#943EC3',
  white: '#FFFFFF',
  dim: 'rgba(255,255,255,0.74)',
  quiet: 'rgba(255,255,255,0.52)',
  faint: 'rgba(255,255,255,0.30)',
  card: 'rgba(255,255,255,0.06)',
  cardBorder: 'rgba(255,255,255,0.10)',
  moon: '#F4F1FF',
};

const T = {
  regular: 'Montserrat_400Regular',
  medium: 'Montserrat_500Medium',
  semibold: 'Montserrat_600SemiBold',
  bold: 'Montserrat_700Bold',
  extra: 'Montserrat_800ExtraBold',
};

function haptic() {
  Haptics.selectionAsync().catch(() => {});
}

// ── Catmull-Rom → cubic bezier, for a smooth wave through the data ───────────
function smoothPath(pts: { x: number; y: number }[]) {
  if (pts.length < 2) return '';
  let d = `M ${pts[0].x},${pts[0].y}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] || p2;
    const cp1x = p1.x + (p2.x - p0.x) / 6;
    const cp1y = p1.y + (p2.y - p0.y) / 6;
    const cp2x = p2.x - (p3.x - p1.x) / 6;
    const cp2y = p2.y - (p3.y - p1.y) / 6;
    d += ` C ${cp1x},${cp1y} ${cp2x},${cp2y} ${p2.x},${p2.y}`;
  }
  return d;
}

// ── A fluffy cloud built from circles + a flat base ─────────────────────────
function Cloud({ x, y, s, opacity = 1 }: { x: number; y: number; s: number; opacity?: number }) {
  return (
    <G opacity={opacity}>
      <Rect x={x - 26 * s} y={y} width={52 * s} height={17 * s} rx={9 * s} fill={C.white} />
      <Circle cx={x - 14 * s} cy={y + 4 * s} r={11 * s} fill={C.white} />
      <Circle cx={x + 2 * s} cy={y - 5 * s} r={15 * s} fill={C.white} />
      <Circle cx={x + 18 * s} cy={y + 2 * s} r={12 * s} fill={C.white} />
    </G>
  );
}

// ── The crescent-moon-in-clouds illustration ────────────────────────────────
function MoonScene({ size }: { size: number }) {
  const h = size * (200 / 230);
  return (
    <Svg width={size} height={h} viewBox="0 0 230 200">
      <Defs>
        <SvgGradient id="moonFill" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#FFFFFF" />
          <Stop offset="1" stopColor="#D9D2F7" />
        </SvgGradient>
        <Mask id="crescent">
          <Circle cx="100" cy="100" r="54" fill="#FFFFFF" />
          <Circle cx="124" cy="84" r="49" fill="#000000" />
        </Mask>
      </Defs>

      {/* Faint orbit rings */}
      <Ellipse cx="105" cy="100" rx="92" ry="44" stroke="rgba(255,255,255,0.16)" strokeWidth="1.2" fill="none" rotation="-22" origin="105, 100" />
      <Ellipse cx="105" cy="100" rx="84" ry="50" stroke="rgba(255,255,255,0.10)" strokeWidth="1.2" fill="none" rotation="16" origin="105, 100" />

      {/* Crescent */}
      <Circle cx="100" cy="100" r="54" fill="url(#moonFill)" mask="url(#crescent)" />

      {/* Clouds — small behind, large in front */}
      <Cloud x={58} y={132} s={0.72} opacity={0.9} />
      <Cloud x={182} y={92} s={0.5} opacity={0.85} />
      <Cloud x={150} y={150} s={1.05} opacity={1} />
    </Svg>
  );
}

// ── Weekly sleep wave chart ─────────────────────────────────────────────────
function WeeklyChart({ width, data }: { width: number; data: number[] }) {
  const H = 132;
  const padL = 26;
  const padTop = 14;
  const padBottom = 20;
  const innerW = width - padL;
  const plotH = H - padTop - padBottom;

  const min = 5.5;
  const max = 8.5;
  const yFor = (v: number) => padTop + (1 - (v - min) / (max - min)) * plotH;
  const xFor = (i: number) => padL + (i / (data.length - 1)) * innerW;

  const pts = data.map((v, i) => ({ x: xFor(i), y: yFor(v) }));
  const line = smoothPath(pts);
  const fill = `${line} L ${pts[pts.length - 1].x},${H - padBottom} L ${pts[0].x},${H - padBottom} Z`;

  const peak = pts.reduce((a, b) => (b.y < a.y ? b : a), pts[0]);
  const grid = [8, 7, 6];

  return (
    <Svg width={width} height={H}>
      <Defs>
        <SvgGradient id="area" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#FFFFFF" stopOpacity="0.28" />
          <Stop offset="1" stopColor="#FFFFFF" stopOpacity="0" />
        </SvgGradient>
      </Defs>

      {grid.map((g) => (
        <G key={g}>
          <Path d={`M ${padL},${yFor(g)} L ${width},${yFor(g)}`} stroke="rgba(255,255,255,0.08)" strokeWidth="1" />
        </G>
      ))}

      <Path d={fill} fill="url(#area)" />
      <Path d={line} stroke={C.white} strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />

      <Circle cx={peak.x} cy={peak.y} r="5.5" fill={C.white} />
      <Circle cx={peak.x} cy={peak.y} r="10" fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="1.5" />
    </Svg>
  );
}

// ── Statistic card ──────────────────────────────────────────────────────────
function StatCard({
  label,
  value,
  progress,
  gradient,
}: {
  label: string;
  value: string;
  progress: number;
  gradient: [string, string];
}) {
  return (
    <LinearGradient
      colors={gradient}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
      style={{
        flex: 1,
        borderRadius: R.lg,
        borderCurve: 'continuous',
        padding: S.lg,
        gap: S.md,
        minHeight: 132,
        justifyContent: 'space-between',
      }}
    >
      <Text style={{ color: C.white, fontFamily: T.semibold, fontSize: 15 }}>{label}</Text>
      <View style={{ gap: S.md }}>
        <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 26 }}>{value}</Text>
        <View style={{ height: 6, borderRadius: 3, backgroundColor: 'rgba(0,0,0,0.22)', overflow: 'hidden' }}>
          <View style={{ width: `${progress * 100}%`, height: '100%', borderRadius: 3, backgroundColor: C.white }} />
        </View>
      </View>
    </LinearGradient>
  );
}

// ── Settings row ────────────────────────────────────────────────────────────
function SettingRow({ label, value, last }: { label: string; value: string; last?: boolean }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={haptic}
      style={({ pressed }) => ({
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        minHeight: 54,
        paddingHorizontal: S.xl,
        borderBottomWidth: last ? 0 : 1,
        borderBottomColor: 'rgba(255,255,255,0.07)',
        opacity: pressed ? 0.6 : 1,
      })}
    >
      <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 15 }}>{label}</Text>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: S.sm }}>
        <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 15 }}>{value}</Text>
        <Text style={{ color: C.faint, fontFamily: T.regular, fontSize: 18 }}>›</Text>
      </View>
    </Pressable>
  );
}

// ── App ──────────────────────────────────────────────────────────────────────
export default function App() {
  const { width } = useWindowDimensions();
  const [bedtime] = useState('10:30 PM');
  const week = [7.1, 7.8, 6.4, 8.0, 6.7, 7.4, 7.9];

  const [fontsLoaded, fontError] = useFonts({
    Montserrat_400Regular,
    Montserrat_500Medium,
    Montserrat_600SemiBold,
    Montserrat_700Bold,
    Montserrat_800ExtraBold,
  });
  if (!fontsLoaded && !fontError) return null;

  const chartW = width - S.xxl * 2 - S.xl * 2;

  return (
    <SafeAreaProvider>
      <LinearGradient colors={[C.bgTop, C.bgBottom]} style={{ flex: 1 }}>
        <StatusBar style="light" />

        {/* Soft background blobs */}
        <View style={{ position: 'absolute', top: -80, right: -100, width: 320, height: 320, borderRadius: 160, backgroundColor: '#3E2A8A', opacity: 0.35 }} />
        <View style={{ position: 'absolute', bottom: 40, left: -120, width: 300, height: 300, borderRadius: 150, backgroundColor: '#7A33B0', opacity: 0.16 }} />

        <SafeAreaView edges={['top', 'bottom']} style={{ flex: 1 }}>
          <ScrollView
            showsVerticalScrollIndicator={false}
            contentInsetAdjustmentBehavior="never"
            contentContainerStyle={{ paddingHorizontal: S.xxl, paddingTop: S.sm, paddingBottom: S.huge, gap: S.xxl }}
          >
            {/* Header */}
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingTop: S.sm }}>
              <View style={{ gap: 2 }}>
                <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 22 }}>Tuesday</Text>
                <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>30 June</Text>
              </View>
              <View style={{ width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', backgroundColor: C.card, borderWidth: 1, borderColor: C.cardBorder }}>
                <Text style={{ color: C.dim, fontFamily: T.bold, fontSize: 18, marginTop: -8 }}>⋯</Text>
              </View>
            </View>

            {/* Hero widget — the moon scene */}
            <View
              style={{
                borderRadius: R.xl,
                borderCurve: 'continuous',
                overflow: 'hidden',
                borderWidth: 1,
                borderColor: C.cardBorder,
              }}
            >
              <LinearGradient colors={['#332176', '#241858']} start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }} style={{ paddingTop: S.xxl, paddingBottom: S.xl, alignItems: 'center' }}>
                {/* Stars */}
                {[[28, 40], [60, 90], [44, 150], [205, 60], [186, 130], [150, 36], [90, 50], [215, 168], [24, 110]].map(([x, y], i) => (
                  <View key={i} style={{ position: 'absolute', left: x, top: y, width: i % 3 === 0 ? 3 : 2, height: i % 3 === 0 ? 3 : 2, borderRadius: 2, backgroundColor: C.white, opacity: 0.5 + (i % 3) * 0.18 }} />
                ))}

                <Text style={{ color: C.white, fontFamily: T.extra, fontSize: 28 }}>Good night</Text>
                <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14, marginTop: S.xs }}>Bedtime · {bedtime}</Text>

                <View style={{ marginTop: S.md, marginBottom: S.md }}>
                  <MoonScene size={236} />
                </View>

                <View style={{ flexDirection: 'row', alignItems: 'center', gap: S.sm, backgroundColor: 'rgba(255,255,255,0.10)', paddingHorizontal: S.lg, paddingVertical: S.sm, borderRadius: R.pill }}>
                  <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 13 }}>Last night</Text>
                  <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 14 }}>7h 24m</Text>
                  <View style={{ width: 4, height: 4, borderRadius: 2, backgroundColor: C.faint }} />
                  <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 14 }}>Score 88</Text>
                </View>
              </LinearGradient>
            </View>

            {/* Primary actions */}
            <View style={{ gap: S.md }}>
              <Pressable
                accessibilityRole="button"
                onPress={haptic}
                style={({ pressed }) => ({
                  minHeight: 58,
                  borderRadius: R.pill,
                  backgroundColor: C.white,
                  alignItems: 'center',
                  justifyContent: 'center',
                  opacity: pressed ? 0.9 : 1,
                  transform: [{ scale: pressed ? 0.99 : 1 }],
                })}
              >
                <Text style={{ color: C.indigo, fontFamily: T.bold, fontSize: 16 }}>Sleep Now</Text>
              </Pressable>

              <Pressable
                accessibilityRole="button"
                onPress={haptic}
                style={({ pressed }) => ({
                  minHeight: 58,
                  borderRadius: R.pill,
                  backgroundColor: C.card,
                  borderWidth: 1,
                  borderColor: C.cardBorder,
                  flexDirection: 'row',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: S.sm,
                  opacity: pressed ? 0.8 : 1,
                })}
              >
                <Text style={{ color: C.white, fontFamily: T.semibold, fontSize: 16 }}>Set Bedtime</Text>
                <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 15 }}>· {bedtime}</Text>
              </Pressable>
            </View>

            {/* Statistics */}
            <View style={{ gap: S.lg }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                <Text style={{ color: C.dim, fontFamily: T.bold, fontSize: 13, letterSpacing: 1 }}>STATISTICS</Text>
                <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>See all</Text>
              </View>
              <View style={{ flexDirection: 'row', gap: S.md }}>
                <StatCard label="Quality" value="88%" progress={0.88} gradient={['#A24BE0', '#7E3CC2']} />
                <StatCard label="Duration" value="7h 24m" progress={0.74} gradient={['#5B45B8', '#3E2D8C']} />
              </View>
            </View>

            {/* Weekly sleep */}
            <View style={{ gap: S.lg }}>
              <Text style={{ color: C.dim, fontFamily: T.bold, fontSize: 13, letterSpacing: 1 }}>WEEKLY SLEEP</Text>
              <View
                style={{
                  backgroundColor: C.card,
                  borderRadius: R.lg,
                  borderCurve: 'continuous',
                  borderWidth: 1,
                  borderColor: C.cardBorder,
                  padding: S.xl,
                  gap: S.sm,
                }}
              >
                <WeeklyChart width={chartW} data={week} />
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', paddingLeft: 26 }}>
                  {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, i) => (
                    <Text key={i} style={{ color: i === week.length - 1 ? C.white : C.faint, fontFamily: T.medium, fontSize: 11 }}>{d}</Text>
                  ))}
                </View>
              </View>
            </View>

            {/* Settings */}
            <View style={{ gap: S.lg }}>
              <Text style={{ color: C.dim, fontFamily: T.bold, fontSize: 13, letterSpacing: 1 }}>SETTINGS</Text>
              <View
                style={{
                  backgroundColor: C.card,
                  borderRadius: R.lg,
                  borderCurve: 'continuous',
                  borderWidth: 1,
                  borderColor: C.cardBorder,
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
