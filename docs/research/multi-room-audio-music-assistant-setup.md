---
type: Research Note
title: Multi-Room Audio Music Assistant Setup
description: Implementation specification for the Louder ESP32-S3 endpoint with Music Assistant and Spotify Connect.
when: Read when configuring or troubleshooting the Music Assistant multi-room audio setup.
resource: modules/aspects/audio.nix
tags: [research, audio, music-assistant, home-assistant]
---

### System Implementation Specification: Louder ESP32-S3 Endpoint

#### 1. Hardware Architecture & Pinout

* **Processor / Board:** Sonocotta Louder ESP32-S3 (ESP32-S3-WROOM-1 module, 8MB PSRAM, 16MB Flash).
* **Audio Subsystem:** Texas Instruments TAS5805M Class-D Amplifier / I2S DAC.
* **Power Supply:** 19V–24V DC / 65W via 5.5 $\times$ 2.1mm DC barrel jack (or 65W USB-C PD on Pro models).
* **Speaker Load:** Passive Bookshelf Pair (4–8 $\Omega$, 85–88 dB sensitivity).

---

#### 2. Firmware Flashing & Hardware Configuration

1. Flash **Squeezelite-ESP32** using the Sonocotta Web Flasher / ESP Web Tools targeting the `TAS5805M` build profile.
2. Join the AP (`Squeezelite-XXXX`), configure the local 2.4 GHz Wi-Fi credentials, and assign a static DHCP lease.
3. Access the Squeezelite-ESP32 Web UI to set the hardware DSP gain ceiling:
* Navigate to **Audio** > **DAC Parameters / Volume Limits**.
* Set **Maximum Hardware Gain / Volume Cap** to `-9 dB` (approx. $75\%$) to eliminate digital clipping and protect drivers from electrical overload.



---

#### 3. Music Assistant & Spotify Connect Configuration

1. In Home Assistant, open **Music Assistant** > **Settings** > **Player Providers** and verify **Slimproto (Squeezebox)** is active.
2. Confirm the Louder ESP32 entity auto-discovers as `media_player.mass_living_room_speakers`.
3. In **Settings** > **Plugins / Player Providers**, enable the **Spotify Connect** provider:
* Select `media_player.mass_living_room_speakers` as an exposed target.
* Set the advertised device name to `Living Room Audio`.
* Configure volume handling to **Relative Stream Gain** (so Spotify app volume adjusts stream attenuation rather than altering the underlying Home Assistant hardware player volume).



---

#### 4. Home Assistant Master Volume Automation

Add this automation to `automations.yaml` to enforce a software ceiling on the room master entity:

```yaml
automation:
  - id: enforce_living_room_max_volume
    alias: "Audio - Clamp Living Room Volume"
    description: "Ensures living room speaker never exceeds master ceiling"
    trigger:
      - platform: numeric_state
        entity_id: media_player.mass_living_room_speakers
        attribute: volume_level
        above: 0.80
    action:
      - action: media_player.volume_set
        target:
          entity_id: media_player.mass_living_room_speakers
        data:
          volume_level: 0.80
    mode: restart

```

---

#### 5. Verification Checklist

* [ ] Verify Squeezelite-ESP32 connects to the Slimproto server port (`3483` / `9000`).
* [ ] Trigger playback from Jellyfin in Music Assistant to confirm gapless FLAC decoding.
* [ ] Open Spotify mobile app on a guest account, connect to `Living Room Audio`, drag the Spotify slider to $100\%$, and verify output level remains strictly within the Home Assistant and TAS5805M gain bounds.
