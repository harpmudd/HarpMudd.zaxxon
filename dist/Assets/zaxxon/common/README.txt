Zaxxon ROMs (supplied by you — not included in this repo):

1. zaxxon.rom  — build it from your own MAME "zaxxon.zip" with the mra tool:
       mra zaxxon.mra        (produces zaxxon.rom)

2. zaxxon_samples.bin — the digitized speech/sound samples (~782 KB).
   These are inline audio DATA (not a CRC recipe), so they are intentionally
   NOT distributed here. Obtain zaxxon_samples.bin by extracting the inline
   WAV blob (<rom index="2">) from the MiSTer Arcade-Zaxxon release
   "Zaxxon (Set 1, Rev D).mra", or use your own samples source.

Place both files in Assets/zaxxon/common/ on your Pocket SD card.
