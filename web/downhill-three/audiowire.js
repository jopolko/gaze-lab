// audiowire.js: every game event -> the Godot sound(s) with Godot's order and arguments, plus the music director's duck/bump.
// Source refs are RunRig.gd / DownhillRig.gd / Fx.gd / AudioHooks.gd / DhDirector.gd (line numbers in the comments). Godot's toon map is applied by sfxset (boom->explosion, coin->blip, boing->sproing).
// createAudioWire({ SFX, GM, PSY, musicTones:false }). GM's own onCue/onChain/onMolecule play synthesized tones that would double the sfxset sounds, so they stay off unless musicTones is true.
export function createAudioWire({ SFX, GM, PSY, musicTones = false, grind = true, wind = false, rumble = false } = {}) {
  const gm = (f, ...a) => { try { if (GM && GM[f]) GM[f](...a); } catch (e) { /* */ } };
  const fire = (name, o) => { try { SFX && SFX.play && SFX.play(name, o); } catch (e) { /* */ } gm('duck'); };          // DhDirector._on_sfx: every sound ducks the music 28 %
  let paused = false, gOn = false, rumbleOn = false;
  const W = {
    sfx: fire,
    // pickups (_take_buff 4765-4779)
    onPickup(t) { fire(t === 'boost' ? 'buff_boost' : t === 'shield' ? 'buff_shield' : t === 'mult' ? 'buff_mult' : 'loot'); },
    onPadHit() { fire('pad_boost'); fire('buff_boost'); },                     // 8170, 8181
    onSpringPad() { fire('pad_boost'); },                                       // 9115
    onVortexGrab() { fire('stretch'); },                                        // 7965
    onRampBlast() { fire('boom'); fire('coin'); fire('snap'); gm('onBump', 0.45); },   // 8049-8054 (boom, cheer coin, snap, music bump)
    onChargedPop() { fire('boing'); },                                          // 8072
    // rails (2001, 9175, 1874-1890)
    onRailStart() { fire('rail_on'); if (grind && SFX.grindOn) { SFX.grindOn(); gOn = true; } },
    onRailGrind(speed) { if (gOn && SFX.grindSpeed) SFX.grindSpeed(speed); },
    onRailEnd(o = {}) { if (gOn && SFX.grindOff) { SFX.grindOff(); gOn = false; } if ((o.sling || 0) > 0.2 && !o.dropped) fire('snap'); if ((o.m || 0) >= 20) fire('cue_good'); fire('coin'); },
    onLand(impact, tAir) { if (impact > 4) fire('land'); if (impact > 2) fire('boing2'); if (impact < 6 && (tAir || 0) > 0.8) fire('cue_good'); },   // 10553-10560
    onSlamLand() { fire('boom'); },                                             // DownhillRig 981
    onSmoothLand() { fire('coin'); },                                           // DownhillRig 993
    onTreeHit() { fire('cue_bad'); fire('splat'); fire('hurt'); fire('thwack'); },   // _crash 5700/5722 then _hit_fx 5636
    onRockHit() { fire('cue_bad'); fire('splat'); fire('hurt'); fire('gong'); },     // 5641
    onShieldBreak() { fire('hurt'); },                                          // 5695
    onCrash() { fire('cue_bad'); fire('splat'); fire('hurt'); },
    onWipeout() { fire('cue_bad'); fire('hurt'); },
    onCheer() { fire('coin'); },                                                // 3970
    onGlint() { try { SFX.glint && SFX.glint(); } catch (e) { /* */ } gm('duck'); },  // 1473 lad ladder (+ coin every 3rd, 3983)
    onGlintBonus() { fire('coin'); },
    onOrb() { fire('coin'); },                                                  // 8815
    onAirRing() { fire('zap'); },                                               // 4023
    onChain(level) { fire('kaboom'); gm('onBump', 0.35); if (musicTones) gm('onChain', level); },   // 9415
    onNod() { fire('boing'); },                                                 // 4353
    onMoleculeFound(i, all) { try { SFX.mol && SFX.mol(i); } catch (e) { /* */ } gm('duck'); gm('onBump', 0.45); if (all) { fire('kaboom'); fire('coin'); } if (musicTones) gm('onMolecule', i); },   // 9820, 9910
    onJumpApex() { fire('cue_good'); if (musicTones) gm('onCue', 1); },        // 9962
    onCue(dir) { fire(dir > 0 ? 'cue_good' : 'cue_bad'); if (musicTones) gm('onCue', dir); },
    // snowball (1371, 1413-1414, 7753, 7832)
    onSnowballWarn() { fire('rumble'); fire('cue_bad'); },
    onSnowballSide() { fire('whoosh'); },
    onSnowballHit() { fire('boom'); },
    onSnowballEscape() { fire('cue_good'); fire('coin'); },
    onSling(phase) { if (phase === 'draw') fire('stretch'); else { fire('snap'); fire('whoosh'); } },   // 10055, 10075-10076
    onGate() { fire('blip'); },                                                 // 10178
    onBump() { fire('boing2'); },                                               // 10266 bumper
    onToyBumper() { fire('boing2'); },
    onToySpring() { fire('boing2'); },
    onToyGate() { fire('blip'); },
    onGoal() { fire('loot'); },                                                 // 729
    onSlalomPole() { fire('coin'); },                                           // 2095
    onRockSmash() { fire('boom'); },                                            // 1978
    onRowPass() { fire('coin'); },                                              // 5926
    onFinish() { fire('boom'); },                                               // 5940
    onFoodBounce(big) { fire(big ? 'boing' : 'squeak'); },                      // 7672, 7686
    onFoodLost() { fire('squeak'); },
    onTrickLaunch() { fire('launch'); },                                        // 11278
    onTrickLand(o = {}) { if (o.slam) { fire('boom'); fire('crowd'); } fire(o.epic || (o.kinds || 0) >= 3 ? 'levelup' : 'buff_mult'); },   // 11447-11452
    onTrickName(k) { fire({ honk: 'honk', boing: 'boing', squeak: 'squeak', bell: 'bell' }[k] || 'bell'); },   // 11171-11185
    onChaos(k) { fire({ honk: 'honk', pop: 'pop', boom: 'boom', crowd: 'crowd' }[k] || 'pop'); },   // 11213-11237
    onFace(k) { fire(k === 'kaboom' ? 'kaboom' : 'bell'); },                    // 11008, 11036
    onPop() { fire('pop'); },
    onWhoosh() { fire('whoosh'); },
    onBoom(at) { fire('boom', at ? { at } : undefined); },                      // Fx.gd 49 (the only positional sound)
    onTubeStart() { fire('pad_boost'); },
    onTubeStep() { fire('coin'); },
    onTubeEnd() { },
    onPause(b) { paused = !!b; gm('setPaused', paused); },
    // continuous: rail pitch via onRailGrind/update; wind per DhDirector._wind_mix (opt-in, Godot ?wind); snowball rumble re-fires by closeness (opt-in)
    update(dt, s = {}) {
      if (gOn && s.railSpeed !== undefined && SFX.grindSpeed) SFX.grindSpeed(s.railSpeed);
      if (SFX.listener && s.pos) SFX.listener(s.pos[0], s.pos[1], s.pos[2], s.heading || 0);
      if (wind && SFX.windUpdate) { if (SFX.windStart) SFX.windStart(); SFX.windUpdate(Math.min(1, (s.speed || 0) / 45), !!s.air, paused, dt); }
      if (rumble && s.snowball !== undefined) { const c = Math.max(0, Math.min(1, s.snowball)); if (c > .05 && !rumbleOn) { rumbleOn = true; fire('rumble'); setTimeout(() => { rumbleOn = false; }, 2500 - 1500 * c); } }
    },
    stop() { if (gOn && SFX.grindOff) SFX.grindOff(); gOn = false; if (SFX.windStop) SFX.windStop(); },
  };
  return W;
}
