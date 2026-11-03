# 8x MSAA on D3DMetal

`msaa8_test.exe` asks D3D11 for an 8x MSAA texture, clears it to one color, and reads all 8
samples back in a compute shader. Run it in a CrossOver bottle that uses D3DMetal:

```
wine msaa8_test.exe
```

On an M3 Max with macOS 27.0.1 and CrossOver Preview with D3DMetal 4.0b3
([`results-d3dmetal.txt`](results-d3dmetal.txt)):

- `CheckMultisampleQualityLevels` reports 0 quality levels for 8 samples, so 8x isn't supported.
- `CreateTexture2D` with 8 samples succeeds anyway, and the texture has 4.
- Samples 0 to 3 read back the clear color, samples 4 to 7 read back 0.

D3D11 expects `CreateTexture2D` to fail when the sample count has no quality levels. A game
that asks for 8x without checking first, like The Wolf Among Us Remastered, never learns it
didn't get it.

Build: `x86_64-w64-mingw32-gcc -O2 -o msaa8_test.exe msaa8_test.c -ld3d11 -ld3dcompiler_47 -ldxguid`
