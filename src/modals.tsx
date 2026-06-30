import { useEffect, useState } from 'react';
import { Modal, Pressable, Text, TextInput, View } from 'react-native';
import { C, fmtClock, Profile, R, S, T } from './core';
import { PrimaryButton, WheelTimePicker } from './ui';

function Sheet({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={{ flex: 1, backgroundColor: 'rgba(8,5,20,0.6)' }} onPress={onClose} />
      <View
        style={{
          backgroundColor: '#221752',
          borderTopLeftRadius: R.xl,
          borderTopRightRadius: R.xl,
          borderTopWidth: 1,
          borderColor: C.hair,
          paddingHorizontal: S.xxl,
          paddingTop: S.lg,
          paddingBottom: S.huge,
          gap: S.xl,
        }}
      >
        <View style={{ alignSelf: 'center', width: 40, height: 5, borderRadius: 3, backgroundColor: C.hair }} />
        {children}
      </View>
    </Modal>
  );
}

export function ScheduleModal({
  bedtime,
  wakeTime,
  onClose,
  onSave,
}: {
  bedtime: number;
  wakeTime: number;
  onClose: () => void;
  onSave: (bed: number, wake: number) => void;
}) {
  const [which, setWhich] = useState<'bed' | 'wake'>('bed');
  const [bed, setBed] = useState(bedtime);
  const [wake, setWake] = useState(wakeTime);

  return (
    <Sheet onClose={onClose}>
      <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 20, textAlign: 'center' }}>Sleep schedule</Text>

      <View style={{ flexDirection: 'row', backgroundColor: C.glass, borderRadius: R.pill, padding: 4 }}>
        {(['bed', 'wake'] as const).map((k) => (
          <Pressable
            key={k}
            onPress={() => setWhich(k)}
            style={{
              flex: 1,
              paddingVertical: S.md,
              borderRadius: R.pill,
              alignItems: 'center',
              backgroundColor: which === k ? C.white : 'transparent',
            }}
          >
            <Text style={{ color: which === k ? C.indigo : C.dim, fontFamily: T.semibold, fontSize: 14 }}>
              {k === 'bed' ? `Bedtime · ${fmtClock(bed)}` : `Wake · ${fmtClock(wake)}`}
            </Text>
          </Pressable>
        ))}
      </View>

      {which === 'bed' ? (
        <WheelTimePicker minutes={bed} onChange={setBed} />
      ) : (
        <WheelTimePicker minutes={wake} onChange={setWake} />
      )}

      <PrimaryButton label="Save schedule" onPress={() => onSave(bed, wake)} />
    </Sheet>
  );
}

export function SettingsModal({
  profile,
  onClose,
  onSaveName,
  onOpenSchedule,
  onReset,
}: {
  profile: Profile;
  onClose: () => void;
  onSaveName: (name: string) => void;
  onOpenSchedule: () => void;
  onReset: () => void;
}) {
  const [name, setName] = useState(profile.name);
  useEffect(() => setName(profile.name), [profile.name]);

  return (
    <Sheet onClose={onClose}>
      <Text style={{ color: C.white, fontFamily: T.bold, fontSize: 20, textAlign: 'center' }}>Settings</Text>

      <View style={{ gap: S.sm }}>
        <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 13 }}>Name</Text>
        <TextInput
          value={name}
          onChangeText={setName}
          onBlur={() => onSaveName(name.trim() || profile.name)}
          placeholder="Your name"
          placeholderTextColor={C.faint}
          style={{
            color: C.white,
            fontFamily: T.semibold,
            fontSize: 18,
            paddingVertical: S.md,
            borderBottomWidth: 1,
            borderBottomColor: C.hair,
          }}
        />
      </View>

      <Pressable
        onPress={onOpenSchedule}
        style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: S.md }}
      >
        <Text style={{ color: C.dim, fontFamily: T.medium, fontSize: 16 }}>Sleep schedule</Text>
        <Text style={{ color: C.quiet, fontFamily: T.medium, fontSize: 15 }}>
          {fmtClock(profile.bedtime)} → {fmtClock(profile.wakeTime)} ›
        </Text>
      </Pressable>

      <Pressable onPress={onReset} style={{ paddingVertical: S.md }}>
        <Text style={{ color: '#F08A9B', fontFamily: T.semibold, fontSize: 15 }}>Reset all data</Text>
      </Pressable>
    </Sheet>
  );
}
