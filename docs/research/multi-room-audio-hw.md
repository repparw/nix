---
type: Research Note
title: Multi-room audio hardware
description: Hardware takeaways and ordering checklist for the Louder ESP32-S3 speaker endpoints.
when: Read when selecting or assembling multi-room audio endpoint hardware.
resource: modules/aspects/audio.nix
tags: [research, audio, music-assistant, esp32]
---

# Multi-room audio hardware

## Physical and hardware takeaways

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

## Audio and system architecture takeaways

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

## Checklist for ordering and assembly

1. **Board.** Sonocotta Louder ESP32-S3, with the built-in antenna, or the Pro
   model if you want USB-C PD power.
2. **Case.** A standard Raspberry Pi 4 plastic or acrylic enclosure.
3. **Power.** A 19 V to 24 V DC, 65 W power brick, or a 65 W PD charger for the
   Pro.
4. **Speakers.** A pair of passive bookshelf speakers rated 4 to 8 ohms, plus
   16 AWG speaker wire.
