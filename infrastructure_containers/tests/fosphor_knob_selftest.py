#!/usr/bin/env python3
"""Checks the fosphor_knob image without an SDR, a knob or a GPU; see README.md.

--crash-loop N runs OpenGL and then OpenCL in N new processes, as fosphor does
at start, and fails if any of them crashed.
"""
import ctypes
import glob
import os
import re
import shutil
import subprocess
import sys

FLOWGRAPHS = '/usr/share/fosphor_knob'
LAUNCHER = '/usr/bin/fosphor_knob'
PROGRAMS = ['lsusb', 'hackrf_sweep', 'bladeRF-cli', 'uhd_find_devices',
            'wmctrl', 'xdotool', 'xtrlock']
UHD_IMAGES = {'usrp_b205mini_fpga.bin', 'usrp_b200_fw.hex'}
DRI_DRIVERS = ['iris', 'radeonsi', 'nouveau', 'swrast']
# pocl, intel-compute-runtime, rocm-opencl-runtime and this image's NVIDIA one
OPENCL_ICDS = ['pocl', 'intel', 'amdocl', 'nvidia']
LIBRARY_DIRS = ['/bin', '/sbin', '/lib64', '/usr/bin', '/usr/sbin', '/usr/lib64',
                '/usr/libexec', '/usr/lib/llvm', '/usr/lib/python3*/site-packages']

CHECKS = []


def check(name):
    def register(func):
        CHECKS.append((name, func))
        return func
    return register


@check('flowgraphs import')
def flowgraphs():
    scripts = sorted(glob.glob(os.path.join(FLOWGRAPHS, 'fosphor_knob_*.py')))
    names = [os.path.basename(s)[:-3] for s in scripts]
    for wide in ('fosphor_knob_bladerf2_wide', 'fosphor_knob_bladerf2_wide_sponsors'):
        if wide not in names:
            raise RuntimeError('%s.py is missing' % wide)
    failed = []
    for script, name in zip(scripts, names):
        if not os.access(script, os.X_OK):
            failed.append('%s is not executable' % name)
            continue
        run = subprocess.run([sys.executable, '-c', 'import ' + name], cwd=FLOWGRAPHS,
                             capture_output=True, text=True)
        if run.returncode:
            failed.append('%s: %s' % (name, run.stderr.strip().splitlines()[-1]))
    if failed:
        raise RuntimeError('; '.join(failed))
    return '%d flowgraphs' % len(names)


@check('fosphor_knob.sh would start the wide bladeRF flowgraphs')
def bladerf_wide():
    with open(LAUNCHER) as f:
        launcher = f.read()
    match = re.search(r'^bladerf_wide_supported\(\) \{\n.*?^\}\n', launcher, re.M | re.S)
    if not match:
        raise RuntimeError('no bladerf_wide_supported() in ' + LAUNCHER)
    run = subprocess.run(['sh', '-c', match.group(0) + 'bladerf_wide_supported\n'],
                         capture_output=True, text=True)
    if run.returncode:
        raise RuntimeError(run.stderr.strip() or 'exit status %d' % run.returncode)


@check('programs fosphor_knob.sh uses')
def programs():
    missing = [p for p in PROGRAMS if not shutil.which(p)]
    if missing:
        raise RuntimeError('missing: ' + ', '.join(missing))


@check('UHD images: only the B205mini ones')
def uhd_images():
    images = set(os.listdir('/usr/share/uhd/images'))
    if images != UHD_IMAGES:
        raise RuntimeError('missing %s, extra %s' % (sorted(UHD_IMAGES - images),
                                                    sorted(images - UHD_IMAGES)))


@check('every ELF file finds its libraries')
def libraries():
    files = []
    for pattern in LIBRARY_DIRS:
        for top in glob.glob(pattern):
            for dirpath, _, filenames in os.walk(top):
                for name in filenames:
                    path = os.path.join(dirpath, name)
                    if os.path.islink(path) or not os.path.isfile(path):
                        continue
                    with open(path, 'rb') as f:
                        if f.read(4) != b'\x7fELF':
                            continue
                    files.append(path)
    broken = {}
    for start in range(0, len(files), 200):
        batch = files[start:start + 200]
        out = subprocess.run(['ldd'] + batch, capture_output=True, text=True).stdout
        current = batch[0]
        for line in out.splitlines():
            if not line.startswith('\t') and line.endswith(':'):
                current = line[:-1]
            elif 'not found' in line:
                lib = line.split()[0]
                # plugins that link a sibling the program loads first, like
                # pocl's device libraries
                if not os.path.exists(os.path.join(os.path.dirname(current), lib)):
                    broken.setdefault(current, []).append(lib)
    if broken:
        raise RuntimeError('; '.join('%s needs %s' % (f, ', '.join(libs))
                                     for f, libs in sorted(broken.items())[:20]))
    return '%d files' % len(files)


@check('a single LLVM')
def single_llvm():
    versions = sorted(os.path.basename(d) for d in glob.glob('/usr/lib/llvm/*'))
    if len(versions) != 1:
        raise RuntimeError('LLVM %s installed' % ', '.join(versions))
    return 'LLVM ' + versions[0]


@check('OpenGL on llvmpipe')
def opengl():
    os.environ['LIBGL_ALWAYS_SOFTWARE'] = '1'
    egl = ctypes.CDLL('libEGL.so.1')
    gl = ctypes.CDLL('libOpenGL.so.0')
    vp = ctypes.c_void_p
    egl.eglGetPlatformDisplay.restype = vp
    egl.eglGetPlatformDisplay.argtypes = [ctypes.c_uint, vp, vp]
    egl.eglInitialize.argtypes = [vp, vp, vp]
    egl.eglChooseConfig.argtypes = [vp, vp, vp, ctypes.c_int, vp]
    egl.eglCreateContext.restype = vp
    egl.eglCreateContext.argtypes = [vp, vp, vp, vp]
    egl.eglMakeCurrent.argtypes = [vp, vp, vp, vp]
    gl.glGetString.restype = ctypes.c_char_p

    display = egl.eglGetPlatformDisplay(0x31DD, None, None)  # EGL_PLATFORM_SURFACELESS_MESA
    if not display or not egl.eglInitialize(display, None, None):
        raise RuntimeError('no EGL display')
    egl.eglBindAPI(0x30A2)  # EGL_OPENGL_API
    # EGL_SURFACE_TYPE: EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE: EGL_OPENGL_BIT
    attribs = (ctypes.c_int * 5)(0x3033, 0x0001, 0x3040, 0x0008, 0x3038)
    config, count = vp(), ctypes.c_int()
    if not egl.eglChooseConfig(display, attribs, ctypes.byref(config), 1, ctypes.byref(count)) \
            or not count.value:
        raise RuntimeError('no EGL config')
    context = egl.eglCreateContext(display, config, None, None)
    if not context or not egl.eglMakeCurrent(display, None, None, context):
        raise RuntimeError('no OpenGL context')
    renderer = (gl.glGetString(0x1F01) or b'').decode()  # GL_RENDERER
    version = (gl.glGetString(0x1F02) or b'').decode()  # GL_VERSION
    if 'llvmpipe' not in renderer:
        raise RuntimeError('renderer is %r' % renderer)
    return '%s, OpenGL %s' % (renderer, version)


KERNEL = b'''
__kernel void square(__global int *data)
{
    int i = get_global_id(0);
    data[i] = data[i] * data[i];
}
'''


def device_info(cl, device, param, size=2048):
    buf = ctypes.create_string_buffer(size)
    cl.clGetDeviceInfo(device, param, size, buf, None)
    return buf.raw


def fosphor_score(cl, device):
    """gr-fosphor's cl_device_score(): None if fosphor can't use the device."""
    uint64 = ctypes.c_uint64
    dtype = uint64.from_buffer_copy(device_info(cl, device, 0x1000, 8)).value  # CL_DEVICE_TYPE
    image = ctypes.c_uint32.from_buffer_copy(device_info(cl, device, 0x1016, 4)).value
    local_mem = uint64.from_buffer_copy(device_info(cl, device, 0x1023, 8)).value
    version = device_info(cl, device, 0x102F).split(b'\0')[0]  # CL_DEVICE_VERSION
    extensions = device_info(cl, device, 0x1030, 16384).split(b'\0')[0]
    vendor = device_info(cl, device, 0x102C).split(b'\0')[0].lower()
    opencl_11 = version.startswith(b'OpenCL 1.') and version[9:10] >= b'1'
    if not image or not (opencl_11 or b'cl_khr_local_int32_base_atomics' in extensions):
        return None
    score = 500 if b'cl_khr_gl_sharing' in extensions else 0
    if dtype & 0x4:  # CL_DEVICE_TYPE_GPU
        score += 1000
        if b'nvidia' in vendor or b'advanced micro devices' in vendor or b'amd' in vendor:
            score += 500
    return score + (local_mem >> 11 if local_mem < 1 << 20 else 1 << 9)


def opencl_run(cl, device):
    """Build and run the square kernel on one device; None if it worked."""
    vp, err = ctypes.c_void_p, ctypes.c_int32()
    dev = vp(device)
    context = cl.clCreateContext(None, 1, ctypes.byref(dev), None, None, ctypes.byref(err))
    if err.value:
        return 'clCreateContext: %d' % err.value
    queue = cl.clCreateCommandQueue(context, device, 0, ctypes.byref(err))
    if err.value:
        return 'clCreateCommandQueue: %d' % err.value
    source = ctypes.c_char_p(KERNEL)
    program = cl.clCreateProgramWithSource(context, 1, ctypes.byref(source), None,
                                           ctypes.byref(err))
    status = cl.clBuildProgram(program, 1, ctypes.byref(dev), None, None, None)
    if status:
        log = ctypes.create_string_buffer(16384)
        cl.clGetProgramBuildInfo(program, device, 0x1183, len(log), log, None)
        return 'clBuildProgram: %d %s' % (status, log.value.decode(errors='replace').strip())
    kernel = cl.clCreateKernel(program, b'square', ctypes.byref(err))
    if err.value:
        return 'clCreateKernel: %d' % err.value
    n = 64
    data = (ctypes.c_int32 * n)(*range(n))
    # CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR
    buf = cl.clCreateBuffer(context, 0x1 | 0x20, ctypes.sizeof(data), data, ctypes.byref(err))
    if err.value:
        return 'clCreateBuffer: %d' % err.value
    cl.clSetKernelArg(kernel, 0, ctypes.sizeof(vp), ctypes.byref(vp(buf)))
    size = ctypes.c_size_t(n)
    status = cl.clEnqueueNDRangeKernel(queue, kernel, 1, None, ctypes.byref(size), None,
                                       0, None, None)
    if status:
        return 'clEnqueueNDRangeKernel: %d' % status
    out = (ctypes.c_int32 * n)()
    status = cl.clEnqueueReadBuffer(queue, buf, 1, 0, ctypes.sizeof(out), out, 0, None, None)
    if status:
        return 'clEnqueueReadBuffer: %d' % status
    if list(out) != [i * i for i in range(n)]:
        return 'wrong results'
    return None


@check('OpenCL kernel on pocl\'s CPU device and any GPU, after OpenGL')
def opencl():
    cl = ctypes.CDLL('libOpenCL.so.1')
    vp = ctypes.c_void_p
    for name in ('clCreateContext', 'clCreateCommandQueue', 'clCreateProgramWithSource',
                 'clCreateKernel', 'clCreateBuffer'):
        getattr(cl, name).restype = vp
    cl.clCreateContext.argtypes = [vp, ctypes.c_uint32, vp, vp, vp, vp]
    cl.clCreateCommandQueue.argtypes = [vp, vp, ctypes.c_uint64, vp]
    cl.clCreateProgramWithSource.argtypes = [vp, ctypes.c_uint32, vp, vp, vp]
    cl.clBuildProgram.argtypes = [vp, ctypes.c_uint32, vp, vp, vp, vp]
    cl.clGetProgramBuildInfo.argtypes = [vp, vp, ctypes.c_uint32, ctypes.c_size_t, vp, vp]
    cl.clCreateKernel.argtypes = [vp, ctypes.c_char_p, vp]
    cl.clCreateBuffer.argtypes = [vp, ctypes.c_uint64, ctypes.c_size_t, vp, vp]
    cl.clSetKernelArg.argtypes = [vp, ctypes.c_uint32, ctypes.c_size_t, vp]
    cl.clEnqueueNDRangeKernel.argtypes = [vp, vp, ctypes.c_uint32, vp, vp, vp,
                                          ctypes.c_uint32, vp, vp]
    cl.clEnqueueReadBuffer.argtypes = [vp, vp, ctypes.c_uint32, ctypes.c_size_t,
                                       ctypes.c_size_t, vp, ctypes.c_uint32, vp, vp]
    cl.clGetPlatformInfo.argtypes = [vp, ctypes.c_uint32, ctypes.c_size_t, vp, vp]
    cl.clGetDeviceIDs.argtypes = [vp, ctypes.c_uint64, ctypes.c_uint32, vp, vp]
    cl.clGetDeviceInfo.argtypes = [vp, ctypes.c_uint32, ctypes.c_size_t, vp, vp]

    count = ctypes.c_uint32()
    cl.clGetPlatformIDs(0, None, ctypes.byref(count))
    platforms = (vp * count.value)()
    cl.clGetPlatformIDs(count.value, platforms, None)
    seen, cpu_ok, problems, best = [], False, [], (-1, None)
    for platform in platforms:
        name = ctypes.create_string_buffer(256)
        cl.clGetPlatformInfo(platform, 0x0902, len(name), name, None)  # CL_PLATFORM_NAME
        pname = name.value.decode()
        ndev = ctypes.c_uint32()
        if cl.clGetDeviceIDs(platform, 0xFFFFFFFF, 0, None, ctypes.byref(ndev)) or not ndev.value:
            seen.append('%s (no devices)' % pname)
            continue
        devices = (vp * ndev.value)()
        cl.clGetDeviceIDs(platform, 0xFFFFFFFF, ndev.value, devices, None)
        for device in devices:
            dname = device_info(cl, device, 0x102B).split(b'\0')[0].decode().strip()
            dtype = ctypes.c_uint64.from_buffer_copy(device_info(cl, device, 0x1000, 8)).value
            score = fosphor_score(cl, device)
            if score is None:
                seen.append('%s: %s (fosphor can\'t use it)' % (pname, dname))
                continue
            problem = opencl_run(cl, device)
            seen.append('%s: %s %s' % (pname, dname, 'ok' if problem is None else 'FAILED'))
            if problem is not None:
                problems.append('%s: %s' % (pname, problem))
                continue
            if pname == 'Portable Computing Language' and dtype & 0x2:  # CL_DEVICE_TYPE_CPU
                cpu_ok = True
            if score > best[0]:
                best = (score, dname)
    if problems or not cpu_ok:
        raise RuntimeError('%s; platforms: %s'
                           % ('; '.join(problems) or "pocl's CPU device is missing", seen))
    return '%s; fosphor picks %s' % ('; '.join(seen), best[1])


@check('Mesa drivers and OpenCL ICDs for every GPU')
def gpu_drivers():
    missing = [d for d in DRI_DRIVERS if not os.path.exists('/usr/lib64/dri/%s_dri.so' % d)]
    icds = os.listdir('/etc/OpenCL/vendors')
    missing += ['%s OpenCL ICD' % i for i in OPENCL_ICDS if not any(i in f for f in icds)]
    if missing:
        raise RuntimeError('missing: ' + ', '.join(missing))
    return 'ICDs: ' + ', '.join(sorted(icds))


def crash_loop(runs):
    code = 'import fosphor_knob_selftest as t; t.opengl(); t.opencl()'
    here = os.path.dirname(os.path.abspath(__file__))
    # pocl's kernel cache would skip the compile, which is what crashed
    env = dict(os.environ, POCL_KERNEL_CACHE='0')
    failed = 0
    for _ in range(runs):
        run = subprocess.run([sys.executable, '-c', code], cwd=here, env=env,
                             capture_output=True)
        if run.returncode:
            failed += 1
    print('%d of %d OpenGL + OpenCL processes failed' % (failed, runs))
    return 1 if failed else 0


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--crash-loop':
        return crash_loop(int(sys.argv[2]))
    failed = 0
    for name, func in CHECKS:
        try:
            detail = func()
            print('PASS  %s%s' % (name, ': ' + detail if detail else ''), flush=True)
        except Exception as e:  # noqa: BLE001 (report every failure, keep going)
            failed += 1
            print('FAIL  %s: %s' % (name, e), flush=True)
    print('\n%d of %d checks passed' % (len(CHECKS) - failed, len(CHECKS)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
