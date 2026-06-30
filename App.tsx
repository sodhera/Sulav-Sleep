import { StatusBar } from 'expo-status-bar';
import { useMemo, useState } from 'react';
import {
  Pressable,
  ScrollView,
  Text,
  TextInput,
  useWindowDimensions,
  View,
} from 'react-native';

type Phase = 'day' | 'windDown' | 'sleepLock' | 'morning';

const palette = {
  background: '#17110F',
  surface: '#241B18',
  surfaceSoft: '#30241F',
  surfaceWarm: '#3A2921',
  text: '#FFF1DC',
  muted: '#C9AA8A',
  quiet: '#917A67',
  amber: '#F1B968',
  ember: '#B95C3E',
  line: '#5B4338',
};

const phases: { id: Phase; label: string }[] = [
  { id: 'day', label: 'Today' },
  { id: 'windDown', label: 'Wind Down' },
  { id: 'sleepLock', label: 'Sleep Lock' },
  { id: 'morning', label: 'Morning' },
];

const sleepBars = [72, 88, 64, 92, 78, 84, 96];
const allowedActions = ['Read', 'Journal', 'Alarm', 'Emergency'];

function getPhaseCopy(phase: Phase) {
  if (phase === 'windDown') {
    return {
      title: 'Wind Down',
      subtitle: 'Apps blocked in 1 hour. Keep only quiet tools visible.',
      metric: '9:30 PM',
      label: 'red filter setup',
    };
  }

  if (phase === 'sleepLock') {
    return {
      title: 'Sleep Lock',
      subtitle: 'Six-hour phone-free window is active.',
      metric: '5h 42m',
      label: 'until check-in',
    };
  }

  if (phase === 'morning') {
    return {
      title: 'Morning Check-in',
      subtitle: 'You made it through the sleep window. Capture the morning.',
      metric: '86',
      label: 'sleep score',
    };
  }

  return {
    title: 'Tonight',
    subtitle: 'Target sleep time is 10:30 PM. Wind Down starts at 9:30 PM.',
    metric: '10:30',
    label: 'bedtime goal',
  };
}

export default function App() {
  const [phase, setPhase] = useState<Phase>('day');
  const [interruptions, setInterruptions] = useState(0);
  const [energy, setEnergy] = useState('Calm');
  const [dream, setDream] = useState('');
  const { width } = useWindowDimensions();

  const phaseCopy = getPhaseCopy(phase);
  const compact = width < 390;

  const sleepScore = useMemo(() => {
    const interruptionPenalty = Math.min(interruptions * 8, 32);
    return Math.max(54, 88 - interruptionPenalty);
  }, [interruptions]);

  return (
    <View style={{ flex: 1, backgroundColor: palette.background }}>
      <StatusBar style="light" />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={{
          padding: compact ? 18 : 24,
          paddingTop: 64,
          paddingBottom: 36,
          gap: 18,
        }}
      >
        <View style={{ gap: 8 }}>
          <Text
            selectable
            style={{
              color: palette.muted,
              fontSize: 14,
              letterSpacing: 0,
              fontWeight: '700',
              textTransform: 'uppercase',
            }}
          >
            Sulav Sleep
          </Text>
          <Text
            selectable
            style={{
              color: palette.text,
              fontSize: 34,
              lineHeight: 39,
              fontWeight: '800',
              letterSpacing: 0,
            }}
          >
            {phaseCopy.title}
          </Text>
          <Text
            selectable
            style={{
              color: palette.muted,
              fontSize: 17,
              lineHeight: 24,
              letterSpacing: 0,
            }}
          >
            {phaseCopy.subtitle}
          </Text>
        </View>

        <View
          style={{
            backgroundColor: palette.surface,
            borderRadius: 30,
            borderCurve: 'continuous',
            padding: 22,
            gap: 18,
            borderWidth: 1,
            borderColor: palette.line,
          }}
        >
          <View
            style={{
              flexDirection: 'row',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              gap: 18,
            }}
          >
            <View style={{ gap: 6, flex: 1 }}>
              <Text
                selectable
                style={{
                  color: palette.text,
                  fontSize: 20,
                  lineHeight: 25,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                Warm screen ready
              </Text>
              <Text
                selectable
                style={{
                  color: palette.muted,
                  fontSize: 15,
                  lineHeight: 21,
                  letterSpacing: 0,
                }}
              >
                Rounded, amber-forward UI designed to stay readable with iOS Color Tint on.
              </Text>
            </View>
            <View
              style={{
                width: 92,
                height: 92,
                borderRadius: 46,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: palette.surfaceWarm,
                borderWidth: 8,
                borderColor: palette.amber,
              }}
            >
              <Text
                selectable
                style={{
                  color: palette.text,
                  fontSize: 28,
                  fontWeight: '900',
                  fontVariant: ['tabular-nums'],
                  letterSpacing: 0,
                }}
              >
                {phase === 'morning' ? sleepScore : phaseCopy.metric}
              </Text>
            </View>
          </View>

          <Text
            selectable
            style={{
              color: palette.quiet,
              fontSize: 13,
              lineHeight: 18,
              letterSpacing: 0,
              textTransform: 'uppercase',
              fontWeight: '700',
            }}
          >
            {phaseCopy.label}
          </Text>
        </View>

        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
          {phases.map((item) => {
            const active = item.id === phase;

            return (
              <Pressable
                key={item.id}
                onPress={() => setPhase(item.id)}
                style={{
                  minHeight: 46,
                  paddingHorizontal: 16,
                  borderRadius: 23,
                  borderCurve: 'continuous',
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: active ? palette.amber : palette.surfaceSoft,
                  borderWidth: 1,
                  borderColor: active ? palette.amber : palette.line,
                }}
              >
                <Text
                  selectable
                  style={{
                    color: active ? '#24160F' : palette.text,
                    fontSize: 15,
                    fontWeight: '800',
                    letterSpacing: 0,
                  }}
                >
                  {item.label}
                </Text>
              </Pressable>
            );
          })}
        </View>

        {(phase === 'windDown' || phase === 'sleepLock') && (
          <View style={{ gap: 12 }}>
            <Text
              selectable
              style={{
                color: palette.text,
                fontSize: 19,
                lineHeight: 24,
                fontWeight: '800',
                letterSpacing: 0,
              }}
            >
              Allowed during night
            </Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
              {allowedActions.map((action) => {
                const emergency = action === 'Emergency';

                return (
                  <Pressable
                    key={action}
                    style={{
                      minWidth: compact ? '47%' : 150,
                      minHeight: 72,
                      flexGrow: 1,
                      borderRadius: 24,
                      borderCurve: 'continuous',
                      backgroundColor: emergency ? '#42231E' : palette.surface,
                      borderWidth: 1,
                      borderColor: emergency ? palette.ember : palette.line,
                      justifyContent: 'center',
                      paddingHorizontal: 18,
                      gap: 4,
                    }}
                  >
                    <Text
                      selectable
                      style={{
                        color: palette.text,
                        fontSize: 17,
                        fontWeight: '800',
                        letterSpacing: 0,
                      }}
                    >
                      {action}
                    </Text>
                    <Text
                      selectable
                      style={{
                        color: emergency ? '#F0A080' : palette.quiet,
                        fontSize: 13,
                        lineHeight: 17,
                        letterSpacing: 0,
                      }}
                    >
                      {emergency ? 'Always available' : 'Quiet action'}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        )}

        {phase === 'sleepLock' && (
          <View
            style={{
              backgroundColor: palette.surface,
              borderRadius: 28,
              borderCurve: 'continuous',
              padding: 20,
              gap: 14,
              borderWidth: 1,
              borderColor: palette.line,
            }}
          >
            <Text
              selectable
              style={{
                color: palette.text,
                fontSize: 19,
                lineHeight: 24,
                fontWeight: '800',
                letterSpacing: 0,
              }}
            >
              Night openings
            </Text>
            <Text
              selectable
              style={{
                color: palette.muted,
                fontSize: 15,
                lineHeight: 21,
                letterSpacing: 0,
              }}
            >
              If the phone is opened during Sleep Lock, we log it as an interruption.
            </Text>
            <Pressable
              onPress={() => setInterruptions((count) => count + 1)}
              style={{
                minHeight: 52,
                borderRadius: 26,
                borderCurve: 'continuous',
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: palette.surfaceWarm,
                borderWidth: 1,
                borderColor: palette.ember,
              }}
            >
              <Text
                selectable
                style={{
                  color: palette.text,
                  fontSize: 16,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                Log night opening ({interruptions})
              </Text>
            </Pressable>
          </View>
        )}

        <View
          style={{
            backgroundColor: palette.surface,
            borderRadius: 28,
            borderCurve: 'continuous',
            padding: 20,
            gap: 16,
            borderWidth: 1,
            borderColor: palette.line,
          }}
        >
          <View
            style={{
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: 16,
            }}
          >
            <View style={{ gap: 4, flex: 1 }}>
              <Text
                selectable
                style={{
                  color: palette.text,
                  fontSize: 19,
                  lineHeight: 24,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                Last 7 nights
              </Text>
              <Text
                selectable
                style={{
                  color: palette.quiet,
                  fontSize: 13,
                  lineHeight: 18,
                  letterSpacing: 0,
                }}
              >
                Score uses height and labels, not color alone.
              </Text>
            </View>
            <Text
              selectable
              style={{
                color: palette.amber,
                fontSize: 20,
                fontWeight: '900',
                fontVariant: ['tabular-nums'],
                letterSpacing: 0,
              }}
            >
              {sleepScore}
            </Text>
          </View>

          <View
            style={{
              height: 120,
              flexDirection: 'row',
              alignItems: 'flex-end',
              gap: 8,
            }}
          >
            {sleepBars.map((score, index) => (
              <View
                key={index}
                style={{
                  flex: 1,
                  gap: 6,
                  alignItems: 'center',
                  justifyContent: 'flex-end',
                }}
              >
                <View
                  style={{
                    width: '100%',
                    minHeight: 18,
                    height: score,
                    borderRadius: 18,
                    borderCurve: 'continuous',
                    backgroundColor: index === sleepBars.length - 1 ? palette.amber : palette.surfaceWarm,
                    borderWidth: 1,
                    borderColor: palette.line,
                  }}
                />
                <Text
                  selectable
                  style={{
                    color: palette.quiet,
                    fontSize: 11,
                    fontVariant: ['tabular-nums'],
                    letterSpacing: 0,
                  }}
                >
                  {index + 1}
                </Text>
              </View>
            ))}
          </View>
        </View>

        {phase === 'morning' && (
          <View style={{ gap: 14 }}>
            <View
              style={{
                backgroundColor: palette.surface,
                borderRadius: 28,
                borderCurve: 'continuous',
                padding: 20,
                gap: 12,
                borderWidth: 1,
                borderColor: palette.line,
              }}
            >
              <Text
                selectable
                style={{
                  color: palette.text,
                  fontSize: 19,
                  lineHeight: 24,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                How did you wake up?
              </Text>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
                {['Calm', 'Tired', 'Clear', 'Restless'].map((item) => {
                  const active = item === energy;

                  return (
                    <Pressable
                      key={item}
                      onPress={() => setEnergy(item)}
                      style={{
                        minHeight: 44,
                        paddingHorizontal: 16,
                        borderRadius: 22,
                        borderCurve: 'continuous',
                        alignItems: 'center',
                        justifyContent: 'center',
                        backgroundColor: active ? palette.amber : palette.surfaceSoft,
                        borderWidth: 1,
                        borderColor: active ? palette.amber : palette.line,
                      }}
                    >
                      <Text
                        selectable
                        style={{
                          color: active ? '#24160F' : palette.text,
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
            </View>

            <View
              style={{
                backgroundColor: palette.surface,
                borderRadius: 28,
                borderCurve: 'continuous',
                padding: 20,
                gap: 12,
                borderWidth: 1,
                borderColor: palette.line,
              }}
            >
              <Text
                selectable
                style={{
                  color: palette.text,
                  fontSize: 19,
                  lineHeight: 24,
                  fontWeight: '800',
                  letterSpacing: 0,
                }}
              >
                Dream check-in
              </Text>
              <TextInput
                multiline
                value={dream}
                onChangeText={setDream}
                placeholder="Write anything you remember..."
                placeholderTextColor={palette.quiet}
                style={{
                  minHeight: 112,
                  borderRadius: 24,
                  borderCurve: 'continuous',
                  backgroundColor: palette.surfaceSoft,
                  borderWidth: 1,
                  borderColor: palette.line,
                  color: palette.text,
                  padding: 16,
                  fontSize: 16,
                  lineHeight: 22,
                  textAlignVertical: 'top',
                  letterSpacing: 0,
                }}
              />
            </View>
          </View>
        )}
      </ScrollView>
    </View>
  );
}
