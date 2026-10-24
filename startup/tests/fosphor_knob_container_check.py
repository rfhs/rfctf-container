#!/usr/bin/env python3
"""Runs inside the fosphor_knob container (see fosphor_knob_start_test.sh).
--no-x and --no-ipc only check that X or MIT-SHM fail; --no-usb and
--no-input skip devices the host doesn't have.
"""
import ctypes
import ctypes.util
import glob
import os
import subprocess
import sys

failures = []


def check(name, ok, detail=""):
    print("%s %s%s" % ("PASS" if ok else "FAIL", name, (": " + detail) if detail else ""))
    if not ok:
        failures.append(name)


def can_open(path, flags):
    try:
        os.close(os.open(path, flags))
        return True, ""
    except OSError as e:
        return False, str(e)


xlib = ctypes.CDLL("libX11.so.6")
xlib.XOpenDisplay.restype = ctypes.c_void_p
xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]

if "--no-x" in sys.argv:
    display = xlib.XOpenDisplay(None)
    check("X server refuses a client without the cookie", not display)
    sys.exit(1 if failures else 0)

display = xlib.XOpenDisplay(None)
check("X connection with the server's cookie (%s)" % os.environ.get("DISPLAY"), bool(display))
if not display:
    sys.exit(1)

# Count X errors instead of exiting on them
errors = []
ERROR_HANDLER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
handler = ERROR_HANDLER(lambda d, e: errors.append(1) or 0)
xlib.XSetErrorHandler(handler)
xlib.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]

# 0666, because an X server not running as root can't attach to the container
# root's 0600 segments the way Mesa and Qt make them; only --ipc=host is tested
xext = ctypes.CDLL("libXext.so.6")
libc = ctypes.CDLL(None, use_errno=True)


class ShmSegmentInfo(ctypes.Structure):
    _fields_ = [("shmseg", ctypes.c_ulong), ("shmid", ctypes.c_int),
                ("shmaddr", ctypes.c_void_p), ("readOnly", ctypes.c_int)]


xext.XShmQueryExtension.argtypes = [ctypes.c_void_p]
xext.XShmAttach.argtypes = [ctypes.c_void_p, ctypes.POINTER(ShmSegmentInfo)]
xext.XShmDetach.argtypes = [ctypes.c_void_p, ctypes.POINTER(ShmSegmentInfo)]
libc.shmat.restype = ctypes.c_void_p
if xext.XShmQueryExtension(display):
    seg = ShmSegmentInfo()
    seg.shmid = libc.shmget(0, 4096, 0o1666)    # IPC_PRIVATE, IPC_CREAT | 0666
    seg.shmaddr = libc.shmat(seg.shmid, None, 0)
    xext.XShmAttach(display, ctypes.byref(seg))
    xlib.XSync(display, 0)
    attached = not errors
    if attached:
        xext.XShmDetach(display, ctypes.byref(seg))
        xlib.XSync(display, 0)
    libc.shmdt(ctypes.c_void_p(seg.shmaddr))
    libc.shmctl(seg.shmid, 0, None)             # IPC_RMID
    if "--no-ipc" in sys.argv:
        check("MIT-SHM fails without the host's IPC namespace", not attached)
        sys.exit(1 if failures else 0)
    check("MIT-SHM: the X server attaches to our shared memory", attached)
    errors.clear()
else:
    check("MIT-SHM extension", False, "the X server doesn't offer it")

gl = ctypes.CDLL("libGL.so.1")
gl.glXChooseVisual.restype = ctypes.c_void_p
gl.glXChooseVisual.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
gl.glXCreateContext.restype = ctypes.c_void_p
gl.glXCreateContext.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
gl.glXMakeCurrent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_void_p]
gl.glXSwapBuffers.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
gl.glGetString.restype = ctypes.c_char_p
xlib.XDefaultScreen.argtypes = [ctypes.c_void_p]
xlib.XRootWindow.restype = ctypes.c_ulong
xlib.XRootWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
xlib.XCreateSimpleWindow.restype = ctypes.c_ulong
xlib.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong] + [ctypes.c_int] * 2 + \
    [ctypes.c_uint] * 3 + [ctypes.c_ulong] * 2
xlib.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]

screen = xlib.XDefaultScreen(display)
attrs = (ctypes.c_int * 5)(4, 5, 8, 0, 0)    # GLX_RGBA, GLX_DOUBLEBUFFER, GLX_RED_SIZE 0, None
visual = gl.glXChooseVisual(display, screen, attrs)
renderer = ""
if visual:
    window = xlib.XCreateSimpleWindow(display, xlib.XRootWindow(display, screen), 0, 0, 64, 64, 0, 0, 0)
    xlib.XMapWindow(display, window)
    context = gl.glXCreateContext(display, visual, None, 1)
    if context and gl.glXMakeCurrent(display, window, context):
        renderer = (gl.glGetString(0x1F01) or b"").decode()   # GL_RENDERER
        gl.glClearColor(ctypes.c_float(1), ctypes.c_float(0), ctypes.c_float(0), ctypes.c_float(1))
        gl.glClear(0x4000)                                     # GL_COLOR_BUFFER_BIT
        gl.glXSwapBuffers(display, window)
        gl.glFinish()
        xlib.XSync(display, 0)
check("OpenGL over GLX draws to a window", bool(renderer) and not errors,
      "%s, %d X errors" % (renderer or "no context", len(errors)))

for node in sorted(glob.glob("/dev/dri/renderD*")):
    check("GPU %s opens" % node, *can_open(node, os.O_RDWR))
if os.path.exists("/dev/kfd"):
    check("/dev/kfd opens", *can_open("/dev/kfd", os.O_RDWR))
if os.path.exists("/dev/nvidiactl"):
    check("/dev/nvidiactl opens", *can_open("/dev/nvidiactl", os.O_RDWR))
usb = sorted(glob.glob("/dev/bus/usb/*/*"))
if "--no-usb" in sys.argv:
    print("SKIP USB devices: the host has none")
else:
    check("USB device nodes are there", bool(usb))
if usb:
    check("USB device %s opens (cgroup rule c 189:*)" % usb[0], *can_open(usb[0], os.O_RDWR))
events = sorted(glob.glob("/dev/input/event*"))
if "--no-input" in sys.argv:
    print("SKIP input devices: the host has none")
else:
    check("input event nodes are there", bool(events))
if events:
    check("input device %s opens (cgroup rule c 13:*)" % events[0], *can_open(events[0], os.O_RDONLY))
if os.path.exists("/usr/bin/lsusb") and "--no-usb" not in sys.argv:
    lsusb = subprocess.run(["lsusb"], capture_output=True, text=True)
    check("lsusb lists the USB devices", lsusb.returncode == 0 and bool(lsusb.stdout.strip()),
          "%d devices" % len(lsusb.stdout.splitlines()))
if os.path.exists("/usr/bin/clinfo"):
    clinfo = subprocess.run(["clinfo", "-l"], capture_output=True, text=True)
    print(clinfo.stdout.rstrip())
    check("clinfo lists OpenCL devices", clinfo.returncode == 0 and "Device" in clinfo.stdout)

sys.exit(1 if failures else 0)
