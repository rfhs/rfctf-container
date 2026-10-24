# Tests for the infrastructure containers

## fosphor_knob_selftest.py

Checks the fosphor_knob image without an SDR, a knob or a GPU: the
flowgraphs import, fosphor_knob.sh would start the wide (oversampled)
bladeRF flowgraphs, every library still resolves after the image's cleanup,
there is only one LLVM (two in one process crash fosphor), OpenGL on
llvmpipe and then an OpenCL kernel on pocl's CPU device work in one process
(as in fosphor), and Mesa's drivers and the OpenCL ICDs for pocl, Intel, ROCm
and NVIDIA are installed. `build-fosphor_knob` runs it before pushing; by
hand, from `infrastructure_containers`:

```sh
docker run --rm --network none -v "$PWD/tests:/tests:ro" rfhs/fosphor_knob \
  python3 /tests/fosphor_knob_selftest.py
```

It prints PASS or FAIL for each check and exits non-zero if any failed.

On a display box, add its GPU to also run the kernel on it (the OpenGL check
stays on llvmpipe): `--device /dev/dri` for Intel and AMD, plus
`--device /dev/kfd` for ROCm, or `--gpus all` for NVIDIA.

`--crash-loop 60` runs OpenGL and then OpenCL in 60 new processes instead,
as fosphor does at start, and fails if any crashed; that is how the two-LLVM
crash showed up (about 1 in 15).
