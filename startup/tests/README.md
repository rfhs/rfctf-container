# Tests for the startup scripts

## fosphor_knob_start_test.sh

Checks the docker arguments `08_fosphor_knob.start` gives the fosphor_knob
container, on whatever machine it runs on, without root and without touching
the running X session. It needs Xvfb, xauth and docker on the host:

```sh
startup/tests/fosphor_knob_start_test.sh [image]    # default rfhs/fosphor_knob
```

It starts its own Xvfb on :97 (`TEST_DISPLAY` picks another) with a cookie
the way a display manager writes one. Then it finds that cookie the way
`rfhs-container-init` does and prints the arguments this machine gets. It
runs the image with exactly those arguments, and inside the container
`fosphor_knob_container_check.py` checks that:

- X lets it in with the cookie;
- MIT-SHM works;
- OpenGL draws to a window over GLX;
- the GPU nodes (/dev/dri, /dev/kfd, /dev/nvidiactl) open, whichever are
  present;
- USB and input device nodes open;
- lsusb and clinfo work.

Two more runs show that the cookie and `--ipc=host` are what make it work:
the X server refuses a run without the cookie, and MIT-SHM fails without
`--ipc=host`. It prints PASS or FAIL for each check and exits non-zero if
any failed.

On Xvfb, OpenGL is always llvmpipe. A GPU's OpenGL, and the display
manager's real cookie, need the display box itself: run
`08_fosphor_knob.start` there.
