import { LinearGradient } from 'expo-linear-gradient';
import { useEffect, useMemo, useRef } from 'react';
import { Animated, Easing, useWindowDimensions, View } from 'react-native';
import Svg, { Circle, Defs, G, LinearGradient as SvgGradient, Mask, Path, Stop } from 'react-native-svg';
import { C } from './core';

/*
 * Background — the base layer. Moon, clouds, stars and mountains live here,
 * NOT inside cards. Each layer takes a different slice of scrollY so they
 * separate into depth as you scroll (parallax), and the clouds drift on
 * their own slow loop. All transforms use the native driver.
 */

function AnimatedLayer({
  scrollY,
  factor,
  children,
  extra,
  style,
}: {
  scrollY: Animated.Value;
  factor: number;
  children: React.ReactNode;
  extra?: any[];
  style?: any;
}) {
  const translateY = scrollY.interpolate({
    inputRange: [0, 1000],
    outputRange: [0, -1000 * factor],
    extrapolate: 'extend',
  });
  return (
    <Animated.View style={[{ position: 'absolute', left: 0, right: 0 }, style, { transform: [{ translateY }, ...(extra || [])] }]}>
      {children}
    </Animated.View>
  );
}

function Crescent({ size }: { size: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 120 120">
      <Defs>
        <SvgGradient id="m" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#FFFFFF" />
          <Stop offset="1" stopColor="#D7CFF6" />
        </SvgGradient>
        <Mask id="c">
          <Circle cx="60" cy="60" r="34" fill="#fff" />
          <Circle cx="76" cy="49" r="30" fill="#000" />
        </Mask>
      </Defs>
      {/* soft glow */}
      <Circle cx="60" cy="60" r="52" fill="rgba(255,255,255,0.05)" />
      <Circle cx="60" cy="60" r="44" fill="rgba(255,255,255,0.06)" />
      <Circle cx="60" cy="60" r="34" fill="url(#m)" mask="url(#c)" />
    </Svg>
  );
}

function Cloud({ w, color = '#FFFFFF', opacity = 1 }: { w: number; color?: string; opacity?: number }) {
  const s = w / 120;
  return (
    <Svg width={w} height={w * 0.5} viewBox="0 0 120 60">
      <G opacity={opacity}>
        <Path
          d="M30 48 Q14 48 12 36 Q10 24 26 22 Q30 8 48 10 Q58 0 72 8 Q90 6 92 24 Q108 24 106 38 Q104 48 90 48 Z"
          fill={color}
        />
      </G>
    </Svg>
  );
}

function Mountains({ width, color, height }: { width: number; color: string; height: number }) {
  // a soft rolling ridge spanning the full width
  const d = `M0 ${height} L0 ${height * 0.55}
    Q ${width * 0.16} ${height * 0.18} ${width * 0.32} ${height * 0.5}
    Q ${width * 0.45} ${height * 0.74} ${width * 0.6} ${height * 0.42}
    Q ${width * 0.76} ${height * 0.08} ${width * 0.9} ${height * 0.46}
    Q ${width * 0.97} ${height * 0.62} ${width} ${height * 0.5}
    L ${width} ${height} Z`;
  return (
    <Svg width={width} height={height}>
      <Path d={d} fill={color} />
    </Svg>
  );
}

export function Background({ scrollY }: { scrollY: Animated.Value }) {
  const { width, height } = useWindowDimensions();
  const drift = useRef(new Animated.Value(0)).current;
  const drift2 = useRef(new Animated.Value(0)).current;
  const twinkle = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const loop = (v: Animated.Value, dur: number) =>
      Animated.loop(
        Animated.sequence([
          Animated.timing(v, { toValue: 1, duration: dur, easing: Easing.inOut(Easing.sin), useNativeDriver: true }),
          Animated.timing(v, { toValue: 0, duration: dur, easing: Easing.inOut(Easing.sin), useNativeDriver: true }),
        ]),
      );
    const a = loop(drift, 16000);
    const b = loop(drift2, 22000);
    const t = loop(twinkle, 2600);
    a.start();
    b.start();
    t.start();
    return () => {
      a.stop();
      b.stop();
      t.stop();
    };
  }, [drift, drift2, twinkle]);

  const stars = useMemo(
    () =>
      Array.from({ length: 42 }).map((_, i) => {
        // deterministic scatter across the upper sky
        const x = (i * 67) % 100;
        const y = ((i * 37) % 56) + 2;
        const r = (i % 4 === 0 ? 1.6 : 1) + (i % 7 === 0 ? 1 : 0);
        const o = 0.35 + ((i * 13) % 50) / 100;
        return { x, y, r, o, big: i % 9 === 0 };
      }),
    [],
  );

  const driftX = drift.interpolate({ inputRange: [0, 1], outputRange: [-14, 14] });
  const driftX2 = drift2.interpolate({ inputRange: [0, 1], outputRange: [16, -16] });
  const starOpacity = twinkle.interpolate({ inputRange: [0, 1], outputRange: [0.75, 1] });

  return (
    <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} pointerEvents="none">
      {/* Sky */}
      <LinearGradient colors={[C.bgTop, C.bgMid, C.bgBottom]} locations={[0, 0.5, 1]} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} />

      {/* Stars — slowest parallax + gentle twinkle */}
      <AnimatedLayer scrollY={scrollY} factor={0.06} style={{ top: 0, height: height * 0.7 }}>
        <Animated.View style={{ opacity: starOpacity }}>
          {stars.map((s, i) => (
            <View
              key={i}
              style={{
                position: 'absolute',
                left: `${s.x}%`,
                top: `${s.y}%`,
                width: s.r,
                height: s.r,
                borderRadius: s.r,
                backgroundColor: '#FFFFFF',
                opacity: s.o,
              }}
            />
          ))}
        </Animated.View>
      </AnimatedLayer>

      {/* Moon */}
      <AnimatedLayer scrollY={scrollY} factor={0.1} style={{ top: height * 0.1, alignItems: 'flex-end' }}>
        <View style={{ marginRight: width * 0.12 }}>
          <Crescent size={132} />
        </View>
      </AnimatedLayer>

      {/* High thin cloud band */}
      <AnimatedLayer scrollY={scrollY} factor={0.14} style={{ top: height * 0.2 }} extra={[{ translateX: driftX2 }]}>
        <View style={{ paddingLeft: width * 0.05 }}>
          <Cloud w={140} opacity={0.1} />
        </View>
      </AnimatedLayer>

      {/* Mid cloud band — drifts the other way */}
      <AnimatedLayer scrollY={scrollY} factor={0.2} style={{ top: height * 0.3 }} extra={[{ translateX: driftX }]}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: width * 0.04 }}>
          <Cloud w={120} opacity={0.16} />
          <Cloud w={90} opacity={0.12} />
        </View>
      </AnimatedLayer>

      {/* Far mountains */}
      <AnimatedLayer scrollY={scrollY} factor={0.26} style={{ bottom: 0, height: height * 0.34, justifyContent: 'flex-end' }}>
        <Mountains width={width} height={height * 0.3} color="#241A52" />
      </AnimatedLayer>

      {/* Near mountains — fastest parallax, reads closest */}
      <AnimatedLayer scrollY={scrollY} factor={0.36} style={{ bottom: -10, height: height * 0.26, justifyContent: 'flex-end' }}>
        <Mountains width={width} height={height * 0.22} color="#160F33" />
      </AnimatedLayer>
    </View>
  );
}
