import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

// ── Palette ──────────────────────────────────────────────────────────────────
const C = {
  bg:        '#07050E',
  ink:       '#FFF5E9',
  inkDim:    '#D7C4B3',
  inkQuiet:  '#A99383',
  amber:     '#F3BA63',
  surface:   '#110F1C',
  border:    '#231D34',
  borderDim: '#1A1528',
};

const F = { body: 'Avenir Next', mono: 'Menlo' };

function haptic() { Haptics.selectionAsync().catch(() => {}); }

// ── 25 stars — fixed positions [x%, y%, size, opacity] ──────────────────────
const STARS: [number, number, number, number][] = [
  [7, 7, 2.0, 0.75],  [20, 4, 1.5, 0.55],  [36, 8, 2.5, 0.88],
  [50, 5, 1.5, 0.60],  [64, 11, 2.0, 0.70],  [79, 6, 2.0, 0.75],
  [92, 15, 1.5, 0.55],  [13, 21, 1.5, 0.60],  [30, 18, 1.0, 0.42],
  [45, 23, 2.0, 0.65],  [58, 16, 1.5, 0.55],  [73, 25, 1.0, 0.45],
  [88, 19, 1.5, 0.60],  [4, 31, 1.5, 0.50],  [18, 37, 1.0, 0.40],
  [34, 32, 2.0, 0.65],  [63, 35, 1.5, 0.55],  [77, 28, 2.0, 0.70],
  [95, 33, 1.0, 0.45],  [25, 45, 1.0, 0.40],  [49, 42, 1.5, 0.55],
  [83, 47, 1.0, 0.40],  [11, 50, 1.5, 0.50],  [57, 49, 1.0, 0.40],
  [39, 53, 1.5, 0.50],
];

// ── Night Art Widget ─────────────────────────────────────────────────────────
function NightWidget({
  score,
  bedtime,
  week,
}: {
  score: number;
  bedtime: string;
  week: number[];
}) {
  const DAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  return (
    <View style={{ height: 370, borderRadius: 28, borderCurve: 'continuous', overflow: 'hidden' }}>

      {/* ── Sky gradient ── */}
      <LinearGradient
        colors={['#0C091E', '#110D2A', '#180F34', '#150C2E']}
        start={{ x: 0.2, y: 0 }}
        end={{ x: 0.8, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />

      {/* ── Stars ── */}
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
            backgroundColor: '#FFF5E9',
            opacity: o,
          }}
        />
      ))}

      {/* ── Nebula smear — very faint ── */}
      <View style={{
        position: 'absolute', top: 82, left: -10, right: -10, height: 20,
        backgroundColor: 'rgba(90, 65, 170, 0.045)',
        transform: [{ rotate: '-3deg' }],
      }} />

      {/* ── Moon — glow halos + crescent core ── */}
      <View style={{ position: 'absolute', top: 14, right: 22, width: 124, height: 124, borderRadius: 62, backgroundColor: 'rgba(243,186,99,0.04)' }} />
      <View style={{ position: 'absolute', top: 26, right: 34, width: 100, height: 100, borderRadius: 50, backgroundColor: 'rgba(243,186,99,0.07)' }} />
      <View style={{ position: 'absolute', top: 38, right: 46, width: 76, height: 76, borderRadius: 38, backgroundColor: 'rgba(255,248,240,0.09)' }} />
      {/* Moon body with crescent */}
      <View style={{
        position: 'absolute', top: 50, right: 58,
        width: 52, height: 52, borderRadius: 26,
        backgroundColor: '#FFF8F0',
        overflow: 'hidden',
      }}>
        {/* Shadow offset right → crescent on left side */}
        <View style={{
          position: 'absolute',
          width: 50, height: 50, borderRadius: 25,
          backgroundColor: '#100B28',
          top: -2, left: 16,
          opacity: 0.93,
        }} />
      </View>

      {/* ── Far mountain peaks (barely distinct from sky) ── */}
      {/* Peak heights: ~200–230px from card bottom */}
      <View style={{ position: 'absolute', bottom: -75, left: 8, width: 55, height: 285, borderRadius: 27, backgroundColor: '#100D28' }} />
      <View style={{ position: 'absolute', bottom: -85, left: 65, width: 62, height: 310, borderRadius: 31, backgroundColor: '#0E0B24' }} />
      <View style={{ position: 'absolute', bottom: -68, left: 130, width: 50, height: 275, borderRadius: 25, backgroundColor: '#130F2E' }} />
      <View style={{ position: 'absolute', bottom: -95, left: 200, width: 68, height: 325, borderRadius: 34, backgroundColor: '#0F0C26' }} />
      <View style={{ position: 'absolute', bottom: -78, left: 275, width: 58, height: 295, borderRadius: 29, backgroundColor: '#12102C' }} />
      <View style={{ position: 'absolute', bottom: -88, left: 340, width: 65, height: 315, borderRadius: 32, backgroundColor: '#0E0B24' }} />

      {/* ── Mid hills (darker, rounded) ── */}
      {/* Peak heights: ~110–135px from card bottom */}
      <View style={{ position: 'absolute', bottom: -65, left: -25, width: 225, height: 200, borderRadius: 112, backgroundColor: '#0C091E' }} />
      <View style={{ position: 'absolute', bottom: -70, right: -20, width: 245, height: 215, borderRadius: 122, backgroundColor: '#0A0818' }} />
      <View style={{ position: 'absolute', bottom: -58, left: '22%', width: 205, height: 190, borderRadius: 102, backgroundColor: '#0B091C' }} />

      {/* ── Near hills (very dark) ── */}
      {/* Peak heights: ~75–95px from card bottom */}
      <View style={{ position: 'absolute', bottom: -75, left: -15, width: 200, height: 165, borderRadius: 100, backgroundColor: '#080615' }} />
      <View style={{ position: 'absolute', bottom: -68, right: -8, width: 218, height: 170, borderRadius: 109, backgroundColor: '#070514' }} />
      <View style={{ position: 'absolute', bottom: -62, left: '36%', width: 185, height: 158, borderRadius: 92, backgroundColor: '#070514' }} />

      {/* ── Ground ── */}
      <View style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 60, backgroundColor: '#04030B' }} />

      {/* ── Bottom readability veil ── */}
      <LinearGradient
        colors={['transparent', 'rgba(4,3,11,0.72)']}
        start={{ x: 0, y: 0 }}
        end={{ x: 0, y: 1 }}
        style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 110 }}
        pointerEvents="none"
      />

      {/* ── Content overlay ── */}
      <View style={{
        position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
        padding: 24,
        justifyContent: 'space-between',
      }}>
        {/* App label */}
        <Text style={{
          color: 'rgba(255,245,233,0.28)',
          fontFamily: F.body, fontSize: 11, fontWeight: '900',
          letterSpacing: 2.5, textTransform: 'uppercase',
        }}>
          Sulav
        </Text>

        {/* Score */}
        <View style={{ gap: 3 }}>
          <Text style={{
            color: C.amber,
            fontFamily: F.mono, fontSize: 82, fontWeight: '900',
            lineHeight: 90, fontVariant: ['tabular-nums'], letterSpacing: -3,
          }}>
            {score}
          </Text>
          <Text style={{
            color: 'rgba(255,245,233,0.40)',
            fontFamily: F.body, fontSize: 11, fontWeight: '800',
            letterSpacing: 2.5, textTransform: 'uppercase',
          }}>
            sleep score
          </Text>
        </View>

        {/* Bedtime + week bars */}
        <View style={{ gap: 16 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <View style={{
              paddingHorizontal: 10, paddingVertical: 5, borderRadius: 999, borderCurve: 'continuous',
              backgroundColor: 'rgba(255,245,233,0.07)',
              borderWidth: 1, borderColor: 'rgba(255,245,233,0.10)',
            }}>
              <Text style={{ color: 'rgba(255,245,233,0.45)', fontFamily: F.body, fontSize: 11, fontWeight: '700' }}>
                tonight
              </Text>
            </View>
            <Text style={{
              color: C.ink, fontFamily: F.mono, fontSize: 22, fontWeight: '900',
              fontVariant: ['tabular-nums'],
            }}>
              {bedtime}
            </Text>
          </View>

          <View style={{ flexDirection: 'row', gap: 7, alignItems: 'flex-end' }}>
            {week.map((s, i) => {
              const today = i === week.length - 1;
              const h = 6 + Math.round((s / 100) * 22);
              return (
                <View key={i} style={{ alignItems: 'center', gap: 5 }}>
                  <View style={{
                    width: 5, height: h, borderRadius: 3,
                    backgroundColor: today ? C.amber : `rgba(255,245,233,${s >= 80 ? 0.36 : 0.20})`,
                  }} />
                  <Text style={{
                    color: today ? C.amber : 'rgba(255,245,233,0.28)',
                    fontFamily: F.body, fontSize: 9, fontWeight: today ? '900' : '600',
                  }}>
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

// ── Action buttons ────────────────────────────────────────────────────────────
function ActionButton({
  label,
  sub,
  variant = 'primary',
  onPress,
}: {
  label: string;
  sub?: string;
  variant?: 'primary' | 'dark';
  onPress?: () => void;
}) {
  const primary = variant === 'primary';
  return (
    <Pressable
      accessibilityRole="button"
      onPress={() => { haptic(); onPress?.(); }}
      style={({ pressed }) => ({
        minHeight: 78,
        borderRadius: 22, borderCurve: 'continuous',
        backgroundColor: primary ? C.amber : C.surface,
        borderWidth: 1,
        borderColor: primary ? '#F6C779' : C.border,
        paddingHorizontal: 24, paddingVertical: 16,
        justifyContent: 'center',
        gap: 4,
        opacity: pressed ? 0.82 : 1,
        transform: [{ scale: pressed ? 0.984 : 1 }],
      })}
    >
      <Text style={{
        color: primary ? '#06050C' : C.ink,
        fontFamily: F.body, fontSize: 19, fontWeight: '900',
      }}>
        {label}
      </Text>
      {sub && (
        <Text style={{
          color: primary ? 'rgba(6,5,12,0.50)' : C.inkQuiet,
          fontFamily: F.mono, fontSize: 13, fontWeight: '700',
          fontVariant: ['tabular-nums'],
        }}>
          {sub}
        </Text>
      )}
    </Pressable>
  );
}

// ── Settings rows ─────────────────────────────────────────────────────────────
function SettingsRow({
  label,
  value,
  accent,
}: {
  label: string;
  value: string;
  accent?: string;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      hitSlop={4}
      onPress={haptic}
      style={({ pressed }) => ({
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingVertical: 15, paddingHorizontal: 18,
        borderRadius: 16, borderCurve: 'continuous',
        backgroundColor: C.surface,
        borderWidth: 1, borderColor: C.borderDim,
        opacity: pressed ? 0.78 : 1,
      })}
    >
      <Text style={{ color: C.inkDim, fontFamily: F.body, fontSize: 15, fontWeight: '700' }}>
        {label}
      </Text>
      <Text style={{
        color: accent ?? C.inkQuiet,
        fontFamily: F.mono, fontSize: 15, fontWeight: '800',
        fontVariant: ['tabular-nums'],
      }}>
        {value}
      </Text>
    </Pressable>
  );
}

// ── App ──────────────────────────────────────────────────────────────────────
export default function App() {
  const [bedtime] = useState('10:30 PM');
  const week = [76, 82, 69, 91, 78, 84, 88];

  return (
    <SafeAreaProvider>
      <LinearGradient colors={['#07050E', '#0C091A', '#07050E']} style={{ flex: 1 }}>
        <StatusBar style="light" />
        <SafeAreaView edges={['top', 'bottom']} style={{ flex: 1 }}>
          <ScrollView
            contentInsetAdjustmentBehavior="never"
            contentContainerStyle={{
              paddingHorizontal: 20,
              paddingTop: 20,
              paddingBottom: 52,
              gap: 14,
            }}
          >
            {/* Night art widget */}
            <NightWidget score={88} bedtime={bedtime} week={week} />

            {/* Stats badges */}
            <View style={{ flexDirection: 'row', gap: 8 }}>
              <View style={{
                paddingHorizontal: 12, paddingVertical: 8,
                borderRadius: 999, borderCurve: 'continuous',
                backgroundColor: 'rgba(243,186,99,0.10)',
                borderWidth: 1, borderColor: 'rgba(243,186,99,0.20)',
              }}>
                <Text style={{ color: C.amber, fontFamily: F.body, fontSize: 13, fontWeight: '900' }}>
                  🌙  5 night streak
                </Text>
              </View>
              <View style={{
                paddingHorizontal: 12, paddingVertical: 8,
                borderRadius: 999, borderCurve: 'continuous',
                backgroundColor: C.surface,
                borderWidth: 1, borderColor: C.borderDim,
              }}>
                <Text style={{ color: C.inkQuiet, fontFamily: F.body, fontSize: 13, fontWeight: '700' }}>
                  Last: 7h 24m
                </Text>
              </View>
            </View>

            {/* Primary actions */}
            <View style={{ gap: 10 }}>
              <ActionButton
                label="Set Bedtime"
                sub={`Currently ${bedtime}`}
                variant="primary"
              />
              <ActionButton
                label="Sleep Now"
                sub="Lock phone for 6 hours"
                variant="dark"
              />
            </View>

            {/* Divider */}
            <View style={{ height: 1, backgroundColor: C.borderDim, marginHorizontal: 4 }} />

            {/* Settings */}
            <View style={{ gap: 8 }}>
              <Text style={{
                color: C.inkQuiet,
                fontFamily: F.body, fontSize: 11, fontWeight: '900',
                letterSpacing: 2, textTransform: 'uppercase',
                paddingHorizontal: 4, marginBottom: 2,
              }}>
                Settings
              </Text>
              <SettingsRow label="Lock duration"       value="6 hours"     accent={C.amber} />
              <SettingsRow label="Wind-down reminder"  value="1 hr before" />
              <SettingsRow label="Morning unlock"      value="6:30 AM" />
              <SettingsRow label="Allowed apps"        value="4 apps →" />
            </View>
          </ScrollView>
        </SafeAreaView>
      </LinearGradient>
    </SafeAreaProvider>
  );
}
