---
type: Research Note
title: Multi-Room Audio Hardware
description: Hardware takeaways and ordering checklist for the Louder ESP32-S3 speaker endpoints.
when: Read when selecting or assembling multi-room audio endpoint hardware.
resource: modules/aspects/audio.nix
tags: [research, audio, music-assistant, esp32]
---

### Physical & Hardware Takeaways

* **Form Factor & Enclosure:** The Louder-ESP32 matches Raspberry Pi 4 dimensions. It mounts inside a standard $3 plastic Pi 4 case (pass the speaker leads through the side GPIO slot) and velcros/tapes directly to the back of one speaker cabinet, leaving zero desktop clutter.
* **Power Supply Details:**
* **Louder-ESP32 / Plus:** Uses a **5.5mm $\times$ 2.1mm DC barrel jack** (19V–24V, ~3A–4A laptop-style brick).
* **Louder-ESP32-Pro:** Uses **USB-C Power Delivery (PD)** directly from a standard 65W GaN laptop charger.
* *Takeaway:* Both yield exactly **one mains wall outlet** powering the microcontroller, DAC, and speaker amplifier simultaneously.


* **Thermal Management:** The onboard Texas Instruments TAS5805M/TAS5825M Class-D amp runs cool under normal listening, but avoid sealing it in an unventilated hollow cavity—the standard vented Pi 4 case provides sufficient passive airflow.
* **Wiring Simplicity:** Only standard 2-conductor speaker wire runs from the board's terminal block to the passive speaker terminals. No analog interconnects (3.5mm/RCA), ground loops, or line hum.

---

### Audio & System Architecture Takeaways

* **Hardware Longevity:** Passive speakers have no digital components or capacitors tied to proprietary cloud servers—they last decades. If Wi-Fi standards change or the board fails, replace only the ~$25 ESP32 module.
* **Acoustic Superiority:** At the ~$140–$180 price point, passive bookshelf speakers (Micca MB42X, Neumi BS5) have larger wooden cabinets, dedicated crossovers, and better driver damping than comparably priced mono smart speakers.
* **Hardware DSP Capabilities:** The TAS5805M/TAS5825M chip runs onboard 15-band parametric EQ, Dynamic Range Compression (DRC), and speaker protection limiters in hardware, offloading all audio processing from the ESP32 CPU.

---

### Final Checklist for Ordering & Assembly

1. **Board:** Sonocotta Louder ESP32-S3 (Built-in antenna, or Pro if you want USB-C PD power).
2. **Case:** Raspberry Pi 4 standard plastic/acrylic enclosure.
3. **Power:** 19V–24V DC / 65W power brick (or 65W PD charger for Pro).
4. **Speakers:** Pair of $4\ \Omega\text{--}8\ \Omega$ passive bookshelves + 16 AWG speaker wire.
