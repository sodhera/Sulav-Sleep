import { LinearGradient } from 'expo-linear-gradient';
import { useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Svg, { Circle, Defs, LinearGradient as SvgGradient, Mask, Stop } from 'react-native-svg';
import { C, fmtClock, Profile, R, S, T } from './core';
import { PrimaryButton, WheelTimePicker } from './ui';

function BigMoon() {
  return (
    <Svg width={96} height={96} viewBox="0 0 120 120">
      <Defs>
        <SvgGradient id="om" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#FFFFFF" />
          <Stop offset="1" stopColor="#D7CFF6" />
        </SvgGradient>
        <Mask id="oc">
          <Circle cx="60" cy="60" r="38" fill="#fff" />
          <Circle cx="78" cy="47" r="33" fill="#000" />
        </Mask>
      </Defs>
      <Circle cx="60" cy="60" r="54" fill="rgba(255,255,255,0.05)" />
      <Circle cx="60" cy="60" r="38" fill="url(#om)" mask="url(#oc)" />
    </Svg>
  );
}

function Dots({ step, total }: { step: number; total: number }) {
  return (
    <View style={{ flexDirection: 'row', gap: S.sm, justifyContent: 'center' }}>
      {Array.from({ length: total }).map((_, i) => (
        <View
          key={i}
          style={{
            width: i === step ? 22 : 7,
            height: 7,
            borderRadius: 4,
            backgroundColor: i === step ? C.white : C.hair,
          }}
        />
      ))}
    </View>
  );
}

export function Onboarding({ onDone }: { onDone: (p: Omit<Profile, 'onboarded'>) => void }) {
  const [step, setStep] = useState(0); // 0 welcome, 1 name, 2 bedtime, 3 wake
  const [name, setName] = useState('');
  const [bedtime, setBedtime] = useState(22 * 60 + 30);
  const [wakeTime, setWakeTime] = useState(6 * 60 + 30);

  const next = () => setStep((s) => s + 1);
  const finish = () => onDone({ name: name.trim() || 'Friend', bedtime, wakeTime });

  return (
    <LinearGradient colors={[C.bgTop, C.bgMid, C.bgBottom]} style={{ flex: 1 }}>
      <SafeAreaView style={{ flex: 1 }}>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <View style={{ flex: 1, paddingHorizontal: S.xxl, paddingTop: S.huge, paddingBottom: S.xxl, justifyContent: 'space-between' }}>
            {/* Top */}
            <View style={{ alignItems: 'center', gap: S.lg }}>
              <BigMoon />
              <Dots step={step} total={4} />
            </View>

            {/* Middle — content per step */}
            <View style={{ flex: 1, justifyContent: 'center', gap: S.xl }}>
              {step === 0 && (
                <View style={{ gap: S.md, alignItems: 'center' }}>
                  <Text style={{ color: C.white, fontFamily: T.extra, fontSize: 30, textAlign: 'center' }}>Sulav Sleep</Text>
                  <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 16, textAlign: 'center', lineHeight: 24, maxWidth: 300 }}>
                    A calmer night. Set a bedtime, quiet the phone, and wake to a gentle picture of your sleep.
                  </Text>
                </View>
              )}

              {step === 1 && (
                <View style={{ gap: S.lg }}>
                  <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 24, textAlign: 'center' }}>What should we call you?</Text>
                  <TextInput
                    value={name}
                    onChangeText={setName}
                    placeholder="Your name"
                    placeholderTextColor={C.faint}
                    autoFocus
                    returnKeyType="done"
                    onSubmitEditing={() => name.trim() && next()}
                    style={{
                      color: C.white,
                      fontFamily: T.semibold,
                      fontSize: 22,
                      textAlign: 'center',
                      paddingVertical: S.md,
                      borderBottomWidth: 1.5,
                      borderBottomColor: C.hair,
                    }}
                  />
                </View>
              )}

              {step === 2 && (
                <View style={{ gap: S.xl }}>
                  <View style={{ gap: S.sm }}>
                    <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 24, textAlign: 'center' }}>When do you usually sleep?</Text>
                    <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14, textAlign: 'center' }}>Around {fmtClock(bedtime)}</Text>
                  </View>
                  <WheelTimePicker minutes={bedtime} onChange={setBedtime} />
                </View>
              )}

              {step === 3 && (
                <View style={{ gap: S.xl }}>
                  <View style={{ gap: S.sm }}>
                    <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 24, textAlign: 'center' }}>And when do you wake?</Text>
                    <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14, textAlign: 'center' }}>Around {fmtClock(wakeTime)}</Text>
                  </View>
                  <WheelTimePicker minutes={wakeTime} onChange={setWakeTime} />
                </View>
              )}
            </View>

            {/* Bottom — actions */}
            <View style={{ gap: S.md }}>
              {step === 0 && <PrimaryButton label="Continue" onPress={next} />}
              {step === 1 && <PrimaryButton label="Next" onPress={() => name.trim() && next()} />}
              {step === 2 && <PrimaryButton label="Next" onPress={next} />}
              {step === 3 && <PrimaryButton label="Start sleeping well" onPress={finish} />}

              {step > 0 && (
                <Pressable onPress={() => setStep((s) => s - 1)} style={{ alignItems: 'center', paddingVertical: S.sm }}>
                  <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 14 }}>Back</Text>
                </Pressable>
              )}
            </View>
          </View>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </LinearGradient>
  );
}
