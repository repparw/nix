---
type: Research Note
title: Multi-room audio Music Assistant setup
description: Implementation specification for the Louder ESP32-S3 endpoint with Music Assistant and Spotify Connect.
when: Read when configuring or troubleshooting the Music Assistant multi-room audio setup.
resource: modules/aspects/audio.nix
tags: [research, audio, music-assistant, home-assistant]
---

# Multi-room audio Music Assistant setup

This page specifies the setup of the Louder ESP32-S3 endpoint.

## 1. Hardware

- **Processor and board.** Sonocotta Louder ESP32-S3 (ESP32-S3-WROOM-1 module,
  8 MB PSRAM, 16 MB flash).
- **Audio subsystem.** Texas Instruments TAS5805M Class-D amplifier and I2S DAC.
- **Power supply.** 19 V to 24 V DC, 65 W, through a 5.5 mm by 2.1 mm DC barrel
  jack, or 65 W USB-C PD on Pro models.
- **Speaker load.** A passive bookshelf pair, 4 to 8 ohms, 85 to 88 dB
  sensitivity.

## 2. Firmware flashing and hardware configuration

1. Flash Squeezelite-ESP32 using the Sonocotta Web Flasher or ESP Web Tools, and
   target the `TAS5805M` build profile.
2. Join the access point `Squeezelite-XXXX`, enter the local 2.4 GHz Wi-Fi
   credentials, and assign a static DHCP lease.
3. Open the Squeezelite-ESP32 web UI and set the hardware DSP gain ceiling:

   - Go to **Audio** > **DAC Parameters / Volume Limits**.
   - Set **Maximum Hardware Gain / Volume Cap** to `-9 dB`. This reduces the output ceiling but does not guarantee
     protection against speaker overload.

## 3. Music Assistant and Spotify Connect configuration

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

## 4. Home Assistant master volume automation

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

## 5. Verification checklist

- [ ] Verify that Squeezelite-ESP32 connects to the Slimproto server port
      (`3483` / `9000`).
- [ ] Start playback from Jellyfin in Music Assistant to confirm gapless FLAC
      decoding.
- [ ] Open the Spotify mobile app on a guest account, connect to
      `Living Room Audio`, and drag the Spotify slider to 100%. Verify that the
      output level stays strictly within the Home Assistant and TAS5805M gain
      limits.
