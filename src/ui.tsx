import { useEffect, useRef } from 'react';
import {
  NativeScrollEvent,
  NativeSyntheticEvent,
  Pressable,
  ScrollView,
  Text,
  View,
} from 'react-native';
import Svg, { Circle, Defs, LinearGradient as SvgGradient, Path, Stop } from 'react-native-svg';
import { C, R, S, T } from './core';

// ── Buttons ──────────────────────────────────────────────────────────────────
export function PrimaryButton({ label, onPress }: { label: string; onPress?: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
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
      <Text style={{ color: C.indigo, fontFamily: T.bold, fontSize: 16 }}>{label}</Text>
    </Pressable>
  );
}

export function GhostButton({ label, value, onPress }: { label: string; value?: string; onPress?: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => ({
        minHeight: 58,
        borderRadius: R.pill,
        backgroundColor: C.glass,
        borderWidth: 1,
        borderColor: C.hair,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center',
        gap: S.sm,
        opacity: pressed ? 0.75 : 1,
      })}
    >
      <Text style={{ color: C.white, fontFamily: T.semibold, fontSize: 16 }}>{label}</Text>
      {value ? <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 15 }}>· {value}</Text> : null}
    </Pressable>
  );
}

// ── Wheel time picker ────────────────────────────────────────────────────────
const ITEM_H = 44;
const VISIBLE = 5;

function WheelColumn({
  values,
  index,
  onChange,
  width,
}: {
  values: string[];
  index: number;
  onChange: (i: number) => void;
  width: number;
}) {
  const ref = useRef<ScrollView>(null);

  useEffect(() => {
    const t = setTimeout(() => ref.current?.scrollTo({ y: index * ITEM_H, animated: false }), 0);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const onEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const i = Math.round(e.nativeEvent.contentOffset.y / ITEM_H);
    const clamped = Math.max(0, Math.min(values.length - 1, i));
    if (clamped !== index) onChange(clamped);
  };

  return (
    <ScrollView
      ref={ref}
      style={{ width, height: ITEM_H * VISIBLE }}
      showsVerticalScrollIndicator={false}
      snapToInterval={ITEM_H}
      decelerationRate="fast"
      onMomentumScrollEnd={onEnd}
      contentContainerStyle={{ paddingVertical: ITEM_H * ((VISIBLE - 1) / 2) }}
    >
      {values.map((v, i) => (
        <View key={i} style={{ height: ITEM_H, alignItems: 'center', justifyContent: 'center' }}>
          <Text
            style={{
              color: i === index ? C.white : C.faint,
              fontFamily: i === index ? T.bold : T.medium,
              fontSize: i === index ? 24 : 20,
            }}
          >
            {v}
          </Text>
        </View>
      ))}
    </ScrollView>
  );
}

const HOURS = Array.from({ length: 12 }, (_, i) => String(i + 1));
const MINUTES = Array.from({ length: 12 }, (_, i) => String(i * 5).padStart(2, '0'));
const PERIODS = ['AM', 'PM'];

export function WheelTimePicker({ minutes, onChange }: { minutes: number; onChange: (m: number) => void }) {
  // decompose minutes-from-midnight into wheel indices
  const h24 = Math.floor(minutes / 60);
  const min = minutes % 60;
  const period = h24 >= 12 ? 1 : 0;
  let h12 = h24 % 12;
  if (h12 === 0) h12 = 12;
  const hourIdx = h12 - 1;
  const minIdx = Math.round(min / 5) % 12;

  const compose = (hi: number, mi: number, pi: number) => {
    let h = (hi + 1) % 12; // 0..11 where 12→0
    if (pi === 1) h += 12; // PM
    onChange((h % 24) * 60 + mi * 5);
  };

  return (
    <View style={{ alignItems: 'center' }}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        {/* center highlight band */}
        <View
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            top: ITEM_H * 2,
            height: ITEM_H,
            borderRadius: R.md,
            backgroundColor: 'rgba(255,255,255,0.07)',
            borderWidth: 1,
            borderColor: C.hair,
          }}
        />
        <WheelColumn values={HOURS} index={hourIdx} width={64} onChange={(i) => compose(i, minIdx, period)} />
        <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 24 }}>:</Text>
        <WheelColumn values={MINUTES} index={minIdx} width={64} onChange={(i) => compose(hourIdx, i, period)} />
        <WheelColumn values={PERIODS} index={period} width={64} onChange={(i) => compose(hourIdx, minIdx, i)} />
      </View>
    </View>
  );
}

// ── Weekly chart (cardless, sits on the background) ──────────────────────────
function smoothPath(pts: { x: number; y: number }[]) {
  if (pts.length < 2) return '';
  let d = `M ${pts[0].x},${pts[0].y}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] || p2;
    d += ` C ${p1.x + (p2.x - p0.x) / 6},${p1.y + (p2.y - p0.y) / 6} ${p2.x - (p3.x - p1.x) / 6},${
      p2.y - (p3.y - p1.y) / 6
    } ${p2.x},${p2.y}`;
  }
  return d;
}

export function WeeklyChart({ width, hours }: { width: number; hours: number[] }) {
  const H = 130;
  const padL = 4;
  const padTop = 14;
  const padBottom = 16;
  const innerW = width - padL;
  const plotH = H - padTop - padBottom;
  const min = 4.5;
  const max = 9;
  const yFor = (v: number) => padTop + (1 - (v - min) / (max - min)) * plotH;
  const xFor = (i: number) => padL + (i / Math.max(1, hours.length - 1)) * innerW;
  const pts = hours.map((v, i) => ({ x: xFor(i), y: yFor(Math.max(min, Math.min(max, v))) }));
  const line = smoothPath(pts);
  const fill = `${line} L ${pts[pts.length - 1].x},${H - padBottom} L ${pts[0].x},${H - padBottom} Z`;
  const peak = pts.reduce((a, b) => (b.y < a.y ? b : a), pts[0]);
  const last = pts[pts.length - 1];

  return (
    <Svg width={width} height={H}>
      <Defs>
        <SvgGradient id="warea" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#FFFFFF" stopOpacity="0.22" />
          <Stop offset="1" stopColor="#FFFFFF" stopOpacity="0" />
        </SvgGradient>
      </Defs>
      {[8, 7, 6, 5].map((g) => (
        <Path key={g} d={`M ${padL},${yFor(g)} L ${width},${yFor(g)}`} stroke="rgba(255,255,255,0.07)" strokeWidth="1" />
      ))}
      <Path d={fill} fill="url(#warea)" />
      <Path d={line} stroke={C.white} strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <Circle cx={peak.x} cy={peak.y} r="4" fill="rgba(255,255,255,0.6)" />
      <Circle cx={last.x} cy={last.y} r="5.5" fill={C.white} />
      <Circle cx={last.x} cy={last.y} r="10" fill="none" stroke="rgba(255,255,255,0.35)" strokeWidth="1.5" />
    </Svg>
  );
}
