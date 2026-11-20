// TUNING: every number a designer would want to change without touching game code. Seconds are seconds, distances are metres.
export const TUNE = {
  grab: { molX: 4.2, molZ: 4, buffX: 3.6, buffZ: 3.2, airX: 4.2, airZ: 3.8, orbX: 2.6, orbZ: 2.4 },          // how close you must be for a pickup to count
  magnet: { seconds: 10, molX: 2, molZ: 1.5, other: 1.6 },          // while it is on: molecule zone x2 sideways and x1.5 along, everything else x1.6
  wings: { seconds: 8, steer: 2, cap: 1.4 },          // air steering strength and the sideways speed cap
  beat: { bpm: 128 },
};
