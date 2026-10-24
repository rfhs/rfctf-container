#!/usr/bin/env python3
"""Where the space goes in a Gentoo/Pentoo image.

Run inside the image (or any Gentoo root). Sizes are of the files each
package installed that are still on disk, from /var/db/pkg/*/*/CONTENTS.

  pkg_sizes.py                      biggest packages
  pkg_sizes.py --base base.txt      only packages that are not in base.txt,
                                    or were reinstalled over it
  pkg_sizes.py --kinds              also split the files into kinds that can
                                    usually go from a runtime image

base.txt lists the base image's packages, one category/package-version per
line, each followed by its merge COUNTER so that packages reinstalled over
the base can be told apart:

  docker run --rm pentoolinux/pentoo-core sh -c \\
    'cd /var/db/pkg && for p in */*; do echo "$p $(cat $p/COUNTER)"; done' > base.txt
"""
import argparse
import collections
import glob
import os
import re

KINDS = [
    ('headers', re.compile(r'^/usr/include/|^/usr/lib/llvm/[^/]+/include/')),
    ('static libraries', re.compile(r'\.a$')),
    ('python opt-1/opt-2 bytecode', re.compile(r'\.opt-[12]\.pyc$')),
    ('python test suites', re.compile(r'/site-packages/.*/tests/')),
    ('man/doc/info', re.compile(r'^/usr/share/(man|doc|info|gtk-doc)/')),
    ('translations', re.compile(r'^/usr/share/locale/')),
    ('UHD images other than B2xx', re.compile(r'^/usr/share/uhd/images/(?!usrp_b2)')),
    ('LLVM tools', re.compile(r'^/usr/lib/llvm/[^/]+/bin/')),
    ('gcc compiler internals', re.compile(r'^/usr/libexec/gcc/')),
]


def is_elf32(path):
    try:
        with open(path, 'rb') as f:
            head = f.read(5)
    except OSError:
        return False
    return head[:4] == b'\x7fELF' and head[4] == 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--base', help='list of base packages to leave out')
    parser.add_argument('--kinds', action='store_true',
                        help='split the files into kinds that can usually go')
    parser.add_argument('-n', type=int, default=40, help='packages to list')
    parser.add_argument('--root', default='/', help='root to look at')
    args = parser.parse_args()

    vdb = os.path.join(args.root, 'var/db/pkg')
    base = {}
    if args.base:
        for line in open(args.base):
            fields = line.split()
            if fields:
                base[fields[0]] = fields[1] if len(fields) > 1 else None

    rows, kinds, seen = [], collections.Counter(), set()
    for pkgdir in glob.glob(os.path.join(vdb, '*/*')):
        name = os.path.relpath(pkgdir, vdb)
        contents = os.path.join(pkgdir, 'CONTENTS')
        if not os.path.exists(contents):
            continue
        reinstalled = False
        if name in base and base[name] is not None:
            with open(os.path.join(pkgdir, 'COUNTER')) as f:
                reinstalled = f.read().strip() != base[name]
        if name in base and not reinstalled:
            continue
        total = 0
        for line in open(contents, errors='replace'):
            if not line.startswith('obj '):
                continue
            path = line[4:].rsplit(' ', 2)[0]
            full = os.path.join(args.root, path.lstrip('/'))
            try:
                size = os.lstat(full).st_size
            except OSError:
                continue
            total += size
            if not args.kinds or path in seen:
                continue
            seen.add(path)
            for label, pattern in KINDS:
                if pattern.search(path):
                    kinds[label] += size
                    break
            else:
                if is_elf32(full):
                    kinds['32-bit ELF files'] += size
        rows.append((total, name + (' (reinstalled over base)' if reinstalled else '')))

    rows.sort(reverse=True)
    print('%.0f MB in %d packages' % (sum(r[0] for r in rows) / 1e6, len(rows)))
    for size, name in rows[:args.n]:
        print('%8.1f MB  %s' % (size / 1e6, name))
    if args.kinds:
        print('\nOf which:')
        for label, size in kinds.most_common():
            print('%8.1f MB  %s' % (size / 1e6, label))


if __name__ == '__main__':
    main()
