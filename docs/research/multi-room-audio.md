---
type: Research Note
title: Multi-room audio
description: Hardware selection, Music Assistant setup, and verification for the Louder ESP32-S3 speaker endpoint.
when: Read when selecting, assembling, or configuring a Louder ESP32-S3 speaker endpoint.
resource: modules/aspects/audio.nix
tags: [research, audio, music-assistant, esp32, home-assistant]
---

# Multi-room audio

These are planning notes, not a declaration of deployed configuration.
Verify hardware specifications and application UI options before using them.

## Hardware selection and ordering

The proposed Sonocotta Louder ESP32-S3 uses an ESP32-S3-WROOM-1 module
(8 MB PSRAM, 16 MB flash), a TAS5805M I2S amplifier/DAC, and a 4 to 8 ohm
passive speaker pair with roughly 85 to 88 dB sensitivity.

### Physical and hardware takeaways

- **Form factor and enclosure.** The Louder-ESP32 matches Raspberry Pi 4
  dimensions. It mounts inside a standard $3 plastic Pi 4 case, with the speaker
  leads passed through the side GPIO slot. Velcro or tape holds the case to the
  back of one speaker cabinet, which leaves no desktop clutter.
- **Power supply.** One mains wall outlet powers the microcontroller, the DAC,
  and the speaker amplifier together.
  - Louder-ESP32 and Plus: a 5.5 mm by 2.1 mm DC barrel jack, 19 V to 24 V, about
    3 A to 4 A from a laptop-style brick.
  - Louder-ESP32-Pro: USB-C Power Delivery (PD) directly from a standard 65 W
    GaN laptop charger.
- **Thermal management.** The onboard Texas Instruments TAS5805M or TAS5825M
  Class-D amplifier runs cool under normal listening. Do not seal it in an
  unventilated hollow cavity. The standard vented Pi 4 case gives enough passive
  airflow.
- **Wiring.** Only standard 2-conductor speaker wire runs from the board's
  terminal block to the passive speaker terminals. There are no analog
  interconnects such as 3.5 mm or RCA, so there are no ground loops or line hum.

### Audio and system architecture takeaways

- **Hardware longevity.** Passive speakers have no digital components or
  capacitors tied to proprietary cloud servers, so they last for decades. If
  Wi-Fi standards change or the board fails, replace only the ESP32 module,
  which costs about $25.
- **Sound quality.** At about $140 to $180, passive bookshelf speakers such as
  the Micca MB42X and Neumi BS5 have larger wooden cabinets, dedicated
  crossovers, and better driver damping than comparably priced mono smart
  speakers.
- **Hardware DSP.** The TAS5805M and TAS5825M chips run a 15-band parametric EQ,
  dynamic range compression (DRC), and speaker protection limiters in hardware.
  This offloads all audio processing from the ESP32 CPU.

### Checklist for ordering and assembly

1. **Board.** Sonocotta Louder ESP32-S3, with the built-in antenna, or the Pro
   model if you want USB-C PD power.
2. **Case.** A standard Raspberry Pi 4 plastic or acrylic enclosure.
3. **Power.** A 19 V to 24 V DC, 65 W power brick, or a 65 W PD charger for the
   Pro.
4. **Speakers.** A pair of passive bookshelf speakers rated 4 to 8 ohms, plus
   16 AWG speaker wire.

## Firmware flashing and hardware configuration

1. Flash Squeezelite-ESP32 using the Sonocotta Web Flasher or ESP Web Tools, and
   target the `TAS5805M` build profile.
2. Join the access point `Squeezelite-XXXX`, enter the local 2.4 GHz Wi-Fi
   credentials, and assign a static DHCP lease.
3. Open the Squeezelite-ESP32 web UI and set the hardware DSP gain ceiling:

   - Go to **Audio** > **DAC Parameters / Volume Limits**.
   - Set **Maximum Hardware Gain / Volume Cap** to `-9 dB`. This reduces the output ceiling but does not guarantee
     protection against speaker overload.

## Music Assistant and Spotify Connect configuration

1. In Home Assistant, open **Music Assistant** > **Settings** > **Player
   Providers**, and verify that **Slimproto (Squeezebox)** is active.
2. Confirm that the Louder ESP32 appears automatically as the entity
   `media_player.mass_living_room_speakers`.
3. In **Settings** > **Plugins / Player Providers**, enable the **Spotify
   Connect** provider:

   - Select `media_player.mass_living_room_speakers` as an exposed target.
   - Set the advertised device name to `Living Room Audio`.
   - Set volume handling to **Relative Stream Gain**. The Spotify app volume then
     adjusts stream attenuation and does not change the underlying Home
     Assistant hardware player volume.

## Home Assistant master volume automation

For a YAML-managed setup, add this list item to `automations.yaml` to set a
software ceiling on the room master entity. Home Assistant also supports
creating this automation through its UI:

```yaml
- id: enforce_living_room_max_volume
  alias: "Audio - Clamp Living Room Volume"
  description: "Clamp living room volume at 80%"
  triggers:
    - trigger: state
      entity_id: media_player.mass_living_room_speakers
      attribute: volume_level
  conditions:
    - condition: numeric_state
      entity_id: media_player.mass_living_room_speakers
      attribute: volume_level
      above: 0.80
  actions:
    - action: media_player.volume_set
      target:
        entity_id: media_player.mass_living_room_speakers
      data:
        volume_level: 0.80
  mode: restart
```

## Verification checklist

- [ ] Verify that Squeezelite-ESP32 connects to the Slimproto server port
      (`3483` / `9000`).
- [ ] Start playback from Jellyfin in Music Assistant to confirm gapless FLAC
      decoding.
- [ ] Open the Spotify mobile app on a guest account, connect to
      `Living Room Audio`, and drag the Spotify slider to 100%. Verify that the
      output level stays strictly within the Home Assistant and TAS5805M gain
      limits.
