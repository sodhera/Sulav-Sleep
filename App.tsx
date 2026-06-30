import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useMemo, useRef, useState } from 'react';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import {
  Animated,
  Easing,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from 'react-native';

type Phase = 'day' | 'windDown' | 'sleepLock' | 'morning';

type PhaseMeta = {
  title: string;
  eyebrow: string;
  summary: string;
  metric: string;
  metricLabel: string;
  state: string;
  accent: string;
  progress: number;
  primaryAction: string;
};

const colors = {
  ink: '#FFF5E9',
  inkDim: '#D7C4B3',
  inkQuiet: '#A99383',
  night: '#0E0B0E',
  night2: '#151014',
  panel: '#201819',
  panel2: '#2A201F',
  panel3: '#352722',
  line: '#5B473D',
  lineSoft: '#3B2F2D',
  ember: '#E56E50',
  amber: '#F3BA63',
  rose: '#D49483',
  moss: '#9AAA86',
  violet: '#8C7BE0',
  danger: '#F08A71',
  black: '#0A0809',
};

const spacing = {
  xs: 6,
  sm: 10,
  md: 16,
  lg: 22,
  xl: 30,
  xxl: 42,
};

const radius = {
  sm: 14,
  md: 20,
  lg: 28,
  xl: 38,
  pill: 999,
};

const type = {
  display: 'Avenir Next',
  body: 'Avenir Next',
  mono: 'Menlo',
};

const phases: { id: Phase; label: string }[] = [
  { id: 'day', label: 'Plan' },
  { id: 'windDown', label: 'Wind Down' },
  { id: 'sleepLock', label: 'Locked' },
  { id: 'morning', label: 'Morning' },
];

const phaseMeta: Record<Phase, PhaseMeta> = {
  day: {
    title: 'Tonight is scheduled',
    eyebrow: 'Sleep Gate',
    summary: 'At 9:30 PM the phone narrows to reading, journaling, alarm, and emergency.',
    metric: '10:30',
    metricLabel: 'bedtime',
    state: 'Ready',
    accent: colors.amber,
    progress: 0.28,
    primaryAction: 'Start wind down',
  },
  windDown: {
    title: 'Wind Down is active',
    eyebrow: 'One hour before bed',
    summary: 'Distracting apps are shielded. The display should be warm, low contrast, and boring.',
    metric: '60',
    metricLabel: 'minutes',
    state: 'Filtering',
    accent: colors.ember,
    progress: 0.5,
    primaryAction: 'Review apps',
  },
  sleepLock: {
    title: 'Sleep Lock is holding',
    eyebrow: 'Six hour commitment',
    summary: 'Opening the phone during this window records an interruption and lowers the sleep score.',
    metric: '5:42',
    metricLabel: 'remaining',
    state: 'Locked',
    accent: colors.rose,
    progress: 0.73,
    primaryAction: 'Log opening',
  },
  morning: {
    title: 'Check in gently',
    eyebrow: 'Wake window',
    summary: 'The phone stayed quiet long enough to count as sleep. Capture energy and any dream trace.',
    metric: '86',
    metricLabel: 'score',
    state: 'Open',
    accent: colors.moss,
    progress: 0.88,
    primaryAction: 'Save morning',
  },
};

const sleepSeries = [
  { day: 'M', score: 76, label: 'Late' },
  { day: 'T', score: 82, label: 'Good' },
  { day: 'W', score: 69, label: 'Open' },
  { day: 'T', score: 91, label: 'Good' },
  { day: 'F', score: 78, label: 'Late' },
  { day: 'S', score: 84, label: 'Good' },
  { day: 'S', score: 88, label: 'Today' },
];

const allowedApps = [
  { name: 'Read', detail: 'Books and saved articles', tone: colors.amber },
  { name: 'Journal', detail: 'Thought dump before lock', tone: colors.rose },
  { name: 'Alarm', detail: 'Wake time only', tone: colors.moss },
  { name: 'Emergency', detail: 'Calls and safety access', tone: colors.danger },
];

const lockRules = [
  { label: '9:30 PM', value: 'Wind Down starts' },
  { label: '10:30 PM', value: 'Sleep Lock begins' },
  { label: '4:30 AM', value: 'Morning check-in opens' },
];

function pressHaptic() {
  Haptics.selectionAsync().catch(() => undefined);
}

function usePhaseAnimation(phase: Phase) {
  const fade = useRef(new Animated.Value(1)).current;
  const lift = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    fade.setValue(0);
    lift.setValue(12);
    Animated.parallel([
      Animated.timing(fade, {
        toValue: 1,
        duration: 260,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      Animated.timing(lift, {
        toValue: 0,
        duration: 320,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
    ]).start();
  }, [fade, lift, phase]);

  return {
    opacity: fade,
    transform: [{ translateY: lift }],
  };
}

function AppButton({
  label,
  onPress,
  variant = 'quiet',
}: {
  label: string;
  onPress?: () => void;
  variant?: 'primary' | 'quiet' | 'danger';
}) {
  const background =
    variant === 'primary' ? colors.amber : variant === 'danger' ? '#3C201E' : colors.panel2;
  const borderColor =
    variant === 'primary' ? colors.amber : variant === 'danger' ? colors.danger : colors.lineSoft;
  const textColor = variant === 'primary' ? colors.black : colors.ink;

  return (
    <Pressable
      accessibilityRole="button"
      hitSlop={8}
      onPress={() => {
        pressHaptic();
        onPress?.();
      }}
      style={({ pressed }) => ({
        minHeight: 54,
        paddingHorizontal: spacing.lg,
        borderRadius: radius.pill,
        borderCurve: 'continuous',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: background,
        borderWidth: 1,
        borderColor,
        opacity: pressed ? 0.82 : 1,
        transform: [{ scale: pressed ? 0.98 : 1 }],
      })}
    >
      <Text
        numberOfLines={1}
        adjustsFontSizeToFit
        style={{
          color: textColor,
          fontFamily: type.body,
          fontSize: 16,
          fontWeight: '800',
          letterSpacing: 0,
        }}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function PhaseControl({
  activePhase,
  onChange,
}: {
  activePhase: Phase;
  onChange: (phase: Phase) => void;
}) {
  return (
    <View
      style={{
        flexDirection: 'row',
        gap: spacing.xs,
        padding: 5,
        borderRadius: radius.pill,
        borderCurve: 'continuous',
        backgroundColor: '#171114',
        borderWidth: 1,
        borderColor: colors.lineSoft,
      }}
    >
      {phases.map((phase) => {
        const active = phase.id === activePhase;

        return (
          <Pressable
            key={phase.id}
            accessibilityLabel={phase.label}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            hitSlop={6}
            onPress={() => {
              pressHaptic();
              onChange(phase.id);
            }}
            style={({ pressed }) => ({
              flex: 1,
              minHeight: 44,
              alignItems: 'center',
              justifyContent: 'center',
              borderRadius: radius.pill,
              borderCurve: 'continuous',
              backgroundColor: active ? colors.ink : 'transparent',
              opacity: pressed ? 0.78 : 1,
            })}
          >
            <Text
              numberOfLines={1}
              adjustsFontSizeToFit
              style={{
                color: active ? colors.black : colors.inkDim,
                fontFamily: type.body,
                fontSize: 13,
                fontWeight: active ? '900' : '700',
                letterSpacing: 0,
              }}
            >
              {phase.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function SleepGate({ meta }: { meta: PhaseMeta }) {
  return (
    <LinearGradient
      colors={['#271C1F', '#161015', '#0F0B0E']}
      start={{ x: 0.08, y: 0 }}
      end={{ x: 0.92, y: 1 }}
      style={{
        minHeight: 360,
        borderRadius: radius.xl,
        borderCurve: 'continuous',
        borderWidth: 1,
        borderColor: colors.line,
        padding: spacing.xl,
        overflow: 'hidden',
      }}
    >
      <View
        style={{
          position: 'absolute',
          width: 260,
          height: 260,
          borderRadius: 130,
          right: -78,
          top: -58,
          borderWidth: 40,
          borderColor: meta.accent,
          opacity: 0.12,
        }}
      />
      <View
        style={{
          position: 'absolute',
          left: -42,
          bottom: -82,
          width: 250,
          height: 250,
          borderRadius: 125,
          backgroundColor: '#513024',
          opacity: 0.28,
        }}
      />

      <View style={{ flex: 1, justifyContent: 'space-between', gap: spacing.xl }}>
        <View style={{ gap: spacing.md }}>
          <View
            style={{
              alignSelf: 'flex-start',
              paddingHorizontal: spacing.md,
              minHeight: 34,
              borderRadius: radius.pill,
              borderCurve: 'continuous',
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: 'rgba(255,245,233,0.08)',
              borderWidth: 1,
              borderColor: 'rgba(255,245,233,0.14)',
            }}
          >
            <Text
              style={{
                color: colors.inkDim,
                fontFamily: type.body,
                fontSize: 12,
                fontWeight: '900',
                letterSpacing: 0,
                textTransform: 'uppercase',
              }}
            >
              {meta.eyebrow}
            </Text>
          </View>

          <Text
            style={{
              color: colors.ink,
              fontFamily: type.display,
              fontSize: 36,
              lineHeight: 41,
              fontWeight: '900',
              letterSpacing: 0,
              maxWidth: 310,
            }}
          >
            {meta.title}
          </Text>
          <Text
            style={{
              color: colors.inkDim,
              fontFamily: type.body,
              fontSize: 16,
              lineHeight: 23,
              letterSpacing: 0,
              maxWidth: 316,
            }}
          >
            {meta.summary}
          </Text>
        </View>

        <View
          style={{
            flexDirection: 'row',
            alignItems: 'flex-end',
            justifyContent: 'space-between',
            gap: spacing.lg,
          }}
        >
          <View
            style={{
              width: 156,
              height: 156,
              borderRadius: 78,
              borderCurve: 'continuous',
              borderWidth: 14,
              borderColor: meta.accent,
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: 'rgba(14,11,14,0.62)',
            }}
          >
            <Text
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.62}
              style={{
                color: colors.ink,
                fontFamily: type.mono,
                fontSize: 36,
                fontWeight: '900',
                fontVariant: ['tabular-nums'],
                letterSpacing: 0,
              }}
            >
              {meta.metric}
            </Text>
            <Text
              style={{
                color: colors.inkQuiet,
                fontFamily: type.body,
                fontSize: 12,
                fontWeight: '800',
                letterSpacing: 0,
                textTransform: 'uppercase',
              }}
            >
              {meta.metricLabel}
            </Text>
          </View>

          <View style={{ flex: 1, gap: spacing.sm, paddingBottom: spacing.sm }}>
            <View
              style={{
                height: 8,
                borderRadius: radius.pill,
                backgroundColor: 'rgba(255,245,233,0.12)',
                overflow: 'hidden',
              }}
            >
              <View
                style={{
                  width: `${meta.progress * 100}%`,
                  height: '100%',
                  borderRadius: radius.pill,
                  backgroundColor: meta.accent,
                }}
              />
            </View>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: spacing.sm }}>
              <Text
                style={{
                  color: colors.inkQuiet,
                  fontFamily: type.body,
                  fontSize: 12,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                9:30
              </Text>
              <Text
                style={{
                  color: meta.accent,
                  fontFamily: type.body,
                  fontSize: 12,
                  fontWeight: '900',
                  letterSpacing: 0,
                }}
              >
                {meta.state}
              </Text>
              <Text
                style={{
                  color: colors.inkQuiet,
                  fontFamily: type.body,
                  fontSize: 12,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                4:30
              </Text>
            </View>
          </View>
        </View>
      </View>
    </LinearGradient>
  );
}

function TimelinePanel() {
  return (
    <View
      style={{
        borderRadius: radius.lg,
        borderCurve: 'continuous',
        backgroundColor: colors.panel,
        borderWidth: 1,
        borderColor: colors.lineSoft,
        padding: spacing.lg,
        gap: spacing.md,
      }}
    >
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: spacing.md }}>
        <View style={{ gap: 4, flex: 1 }}>
          <Text
            style={{
              color: colors.ink,
              fontFamily: type.body,
              fontSize: 18,
              lineHeight: 23,
              fontWeight: '900',
              letterSpacing: 0,
            }}
          >
            Tonight's mechanism
          </Text>
          <Text
            style={{
              color: colors.inkQuiet,
              fontFamily: type.body,
              fontSize: 14,
              lineHeight: 20,
              letterSpacing: 0,
            }}
          >
            Clear sequence, no mystery settings at night.
          </Text>
        </View>
        <View
          style={{
            minWidth: 70,
            minHeight: 42,
            borderRadius: radius.md,
            borderCurve: 'continuous',
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: colors.panel3,
          }}
        >
          <Text
            style={{
              color: colors.amber,
              fontFamily: type.mono,
              fontSize: 16,
              fontWeight: '900',
              fontVariant: ['tabular-nums'],
              letterSpacing: 0,
            }}
          >
            6h
          </Text>
        </View>
      </View>

      {lockRules.map((rule, index) => (
        <View
          key={rule.label}
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: spacing.md,
          }}
        >
          <View style={{ alignItems: 'center', width: 18 }}>
            <View
              style={{
                width: 12,
                height: 12,
                borderRadius: 6,
                backgroundColor: index === 1 ? colors.amber : colors.panel3,
                borderWidth: 1,
                borderColor: colors.line,
              }}
            />
          </View>
          <Text
            style={{
              width: 78,
              color: colors.ink,
              fontFamily: type.mono,
              fontSize: 13,
              fontWeight: '800',
              fontVariant: ['tabular-nums'],
              letterSpacing: 0,
            }}
          >
            {rule.label}
          </Text>
          <Text
            style={{
              flex: 1,
              color: colors.inkDim,
              fontFamily: type.body,
              fontSize: 14,
              lineHeight: 20,
              letterSpacing: 0,
            }}
          >
            {rule.value}
          </Text>
        </View>
      ))}
    </View>
  );
}

function AllowedAppsPanel() {
  return (
    <View style={{ gap: spacing.md }}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: spacing.md }}>
        <View style={{ gap: 4, flex: 1 }}>
          <Text
            style={{
              color: colors.ink,
              fontFamily: type.body,
              fontSize: 19,
              lineHeight: 24,
              fontWeight: '900',
              letterSpacing: 0,
            }}
          >
            Night shelf
          </Text>
          <Text
            style={{
              color: colors.inkQuiet,
              fontFamily: type.body,
              fontSize: 14,
              lineHeight: 20,
              letterSpacing: 0,
            }}
          >
            Few choices, large targets, no feed surfaces.
          </Text>
        </View>
      </View>

      <View style={{ gap: spacing.sm }}>
        {allowedApps.map((app) => (
          <Pressable
            key={app.name}
            accessibilityRole="button"
            hitSlop={6}
            onPress={pressHaptic}
            style={({ pressed }) => ({
              minHeight: 72,
              borderRadius: radius.lg,
              borderCurve: 'continuous',
              backgroundColor: colors.panel,
              borderWidth: 1,
              borderColor: colors.lineSoft,
              padding: spacing.md,
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.md,
              opacity: pressed ? 0.82 : 1,
              transform: [{ scale: pressed ? 0.99 : 1 }],
            })}
          >
            <View
              style={{
                width: 44,
                height: 44,
                borderRadius: 22,
                borderCurve: 'continuous',
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: `${app.tone}24`,
                borderWidth: 1,
                borderColor: `${app.tone}88`,
              }}
            >
              <Text
                style={{
                  color: app.tone,
                  fontFamily: type.body,
                  fontSize: 13,
                  fontWeight: '900',
                  letterSpacing: 0,
                }}
              >
                {app.name.slice(0, 2).toUpperCase()}
              </Text>
            </View>
            <View style={{ flex: 1, gap: 3 }}>
              <Text
                style={{
                  color: colors.ink,
                  fontFamily: type.body,
                  fontSize: 16,
                  fontWeight: '900',
                  letterSpacing: 0,
                }}
              >
                {app.name}
              </Text>
              <Text
                style={{
                  color: colors.inkQuiet,
                  fontFamily: type.body,
                  fontSize: 13,
                  lineHeight: 18,
                  letterSpacing: 0,
                }}
              >
                {app.detail}
              </Text>
            </View>
            <Text
              style={{
                color: colors.inkQuiet,
                fontFamily: type.body,
                fontSize: 20,
                fontWeight: '600',
                letterSpacing: 0,
              }}
            >
              {'>'}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

function ScorePanel({ score }: { score: number }) {
  return (
    <View
      style={{
        borderRadius: radius.lg,
        borderCurve: 'continuous',
        backgroundColor: colors.panel,
        borderWidth: 1,
        borderColor: colors.lineSoft,
        padding: spacing.lg,
        gap: spacing.lg,
      }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' }}>
        <View style={{ gap: 4, flex: 1 }}>
          <Text
            style={{
              color: colors.ink,
              fontFamily: type.body,
              fontSize: 19,
              lineHeight: 24,
              fontWeight: '900',
              letterSpacing: 0,
            }}
          >
            Rhythm, not decoration
          </Text>
          <Text
            style={{
              color: colors.inkQuiet,
              fontFamily: type.body,
              fontSize: 14,
              lineHeight: 20,
              letterSpacing: 0,
            }}
          >
            Bar height shows score. Labels flag late or interrupted nights.
          </Text>
        </View>
        <View style={{ alignItems: 'flex-end', gap: 2 }}>
          <Text
            style={{
              color: colors.amber,
              fontFamily: type.mono,
              fontSize: 30,
              fontWeight: '900',
              fontVariant: ['tabular-nums'],
              letterSpacing: 0,
            }}
          >
            {score}
          </Text>
          <Text
            style={{
              color: colors.inkQuiet,
              fontFamily: type.body,
              fontSize: 11,
              fontWeight: '800',
              letterSpacing: 0,
              textTransform: 'uppercase',
            }}
          >
            sleep score
          </Text>
        </View>
      </View>

      <View style={{ height: 148, flexDirection: 'row', alignItems: 'flex-end', gap: 9 }}>
        {sleepSeries.map((item, index) => {
          const active = index === sleepSeries.length - 1;
          const marked = item.label === 'Open';

          return (
            <View
              key={`${item.day}-${index}`}
              style={{ flex: 1, alignItems: 'center', justifyContent: 'flex-end', gap: 7 }}
            >
              <View
                style={{
                  width: '100%',
                  height: item.score,
                  minHeight: 22,
                  borderRadius: radius.pill,
                  borderCurve: 'continuous',
                  backgroundColor: active ? colors.amber : colors.panel3,
                  borderWidth: 1,
                  borderColor: active ? '#F6C779' : colors.line,
                  justifyContent: 'flex-start',
                  alignItems: 'center',
                  paddingTop: marked ? 5 : 0,
                }}
              >
                {marked && (
                  <View
                    style={{
                      width: 7,
                      height: 7,
                      borderRadius: 4,
                      backgroundColor: colors.danger,
                    }}
                  />
                )}
              </View>
              <Text
                style={{
                  color: active ? colors.ink : colors.inkQuiet,
                  fontFamily: type.body,
                  fontSize: 12,
                  fontWeight: active ? '900' : '700',
                  letterSpacing: 0,
                }}
              >
                {item.day}
              </Text>
            </View>
          );
        })}
      </View>
    </View>
  );
}

function MorningPanel({
  energy,
  dream,
  onEnergy,
  onDream,
}: {
  energy: string;
  dream: string;
  onEnergy: (value: string) => void;
  onDream: (value: string) => void;
}) {
  return (
    <View
      style={{
        borderRadius: radius.lg,
        borderCurve: 'continuous',
        backgroundColor: colors.panel,
        borderWidth: 1,
        borderColor: colors.lineSoft,
        padding: spacing.lg,
        gap: spacing.lg,
      }}
    >
      <View style={{ gap: 4 }}>
        <Text
          style={{
            color: colors.ink,
            fontFamily: type.body,
            fontSize: 19,
            lineHeight: 24,
            fontWeight: '900',
            letterSpacing: 0,
          }}
        >
          Morning capture
        </Text>
        <Text
          style={{
            color: colors.inkQuiet,
            fontFamily: type.body,
            fontSize: 14,
            lineHeight: 20,
            letterSpacing: 0,
          }}
        >
          Fast enough for groggy mornings, open enough for dream recall.
        </Text>
      </View>

      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
        {['Calm', 'Heavy', 'Clear', 'Restless'].map((item) => {
          const active = item === energy;

          return (
            <Pressable
              key={item}
              accessibilityRole="button"
              accessibilityState={{ selected: active }}
              hitSlop={6}
              onPress={() => {
                pressHaptic();
                onEnergy(item);
              }}
              style={({ pressed }) => ({
                minHeight: 46,
                paddingHorizontal: spacing.md,
                borderRadius: radius.pill,
                borderCurve: 'continuous',
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: active ? colors.ink : colors.panel2,
                borderWidth: 1,
                borderColor: active ? colors.ink : colors.lineSoft,
                opacity: pressed ? 0.8 : 1,
              })}
            >
              <Text
                style={{
                  color: active ? colors.black : colors.ink,
                  fontFamily: type.body,
                  fontSize: 15,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                {item}
              </Text>
            </Pressable>
          );
        })}
      </View>

      <TextInput
        multiline
        value={dream}
        onChangeText={onDream}
        placeholder="Dream fragment, feeling, image, or nothing at all..."
        placeholderTextColor={colors.inkQuiet}
        style={{
          minHeight: 122,
          borderRadius: radius.lg,
          borderCurve: 'continuous',
          backgroundColor: colors.panel2,
          borderWidth: 1,
          borderColor: colors.lineSoft,
          color: colors.ink,
          padding: spacing.md,
          fontFamily: type.body,
          fontSize: 16,
          lineHeight: 23,
          textAlignVertical: 'top',
          letterSpacing: 0,
        }}
      />
    </View>
  );
}

export default function App() {
  const [phase, setPhase] = useState<Phase>('day');
  const [interruptions, setInterruptions] = useState(0);
  const [energy, setEnergy] = useState('Calm');
  const [dream, setDream] = useState('');
  const { width } = useWindowDimensions();
  const animatedStyle = usePhaseAnimation(phase);

  const compact = width < 390;
  const meta = phaseMeta[phase];
  const sleepScore = useMemo(() => Math.max(54, 88 - Math.min(interruptions * 8, 32)), [interruptions]);

  return (
    <SafeAreaProvider>
      <LinearGradient colors={[colors.night, colors.night2, '#120D0C']} style={{ flex: 1 }}>
        <StatusBar style="light" />
        <SafeAreaView edges={['top', 'bottom']} style={{ flex: 1 }}>
        <ScrollView
          contentInsetAdjustmentBehavior="never"
          contentContainerStyle={{
            paddingHorizontal: compact ? spacing.md : spacing.lg,
            paddingTop: spacing.xl,
            paddingBottom: 44,
            gap: spacing.lg,
          }}
        >
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
            <View style={{ gap: 3 }}>
              <Text
                style={{
                  color: colors.inkQuiet,
                  fontFamily: type.body,
                  fontSize: 12,
                  fontWeight: '900',
                  letterSpacing: 0,
                  textTransform: 'uppercase',
                }}
              >
                Sulav Sleep
              </Text>
              <Text
                style={{
                  color: colors.ink,
                  fontFamily: type.body,
                  fontSize: 15,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                10:30 PM target
              </Text>
            </View>
            <View
              style={{
                minHeight: 40,
                paddingHorizontal: spacing.md,
                borderRadius: radius.pill,
                borderCurve: 'continuous',
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: 'rgba(243,186,99,0.12)',
                borderWidth: 1,
                borderColor: 'rgba(243,186,99,0.36)',
              }}
            >
              <Text
                style={{
                  color: colors.amber,
                  fontFamily: type.body,
                  fontSize: 13,
                  fontWeight: '900',
                  letterSpacing: 0,
                }}
              >
                Red filter safe
              </Text>
            </View>
          </View>

          <PhaseControl activePhase={phase} onChange={setPhase} />

          <Animated.View style={[animatedStyle, { gap: spacing.lg }]}>
            <SleepGate meta={meta} />

            <View style={{ flexDirection: compact ? 'column' : 'row', gap: spacing.md }}>
              <View style={{ flex: 1 }}>
                <AppButton
                  label={phase === 'sleepLock' ? `${meta.primaryAction} (${interruptions})` : meta.primaryAction}
                  variant={phase === 'sleepLock' ? 'danger' : 'primary'}
                  onPress={() => {
                    if (phase === 'sleepLock') {
                      setInterruptions((count) => count + 1);
                    } else if (phase === 'day') {
                      setPhase('windDown');
                    }
                  }}
                />
              </View>
              <View style={{ flex: 1 }}>
              <AppButton label="Filter guide" />
              </View>
            </View>

            <TimelinePanel />

            {(phase === 'windDown' || phase === 'sleepLock') && <AllowedAppsPanel />}

            {phase === 'morning' && (
              <MorningPanel energy={energy} dream={dream} onEnergy={setEnergy} onDream={setDream} />
            )}

            <ScorePanel score={sleepScore} />
          </Animated.View>
        </ScrollView>
        </SafeAreaView>
      </LinearGradient>
    </SafeAreaProvider>
  );
}
