#!/usr/bin/env python3
"""Checks the contestants' seccomp and AppArmor profiles against docker's current defaults.

Docker can't extend its default profiles, only replace them, so the
contestants' are copies of moby/profiles' plus their own rules:
startup/rfhs-contestant-seccomp.json is seccomp/default.json with the rules
whose comment starts with "rfhs-contestant:" added at the end, and
misc/contestant_apparmor's profile is apparmor/template.go's rendered for
rfhs-contestant without the rules in APPARMOR_DROPPED, followed by its own
rules from the ${userns} line. This
fails if either is not exactly that for moby/profiles' main branch now, so
docker's security fixes reach the contestants. --sync rewrites both from it.

  ./tools/check_contestant_profiles.py
  ./tools/check_contestant_profiles.py --sync
"""
import difflib
import json
import os
import re
import sys
import urllib.request

UPSTREAM = 'https://raw.githubusercontent.com/moby/profiles/main/'
REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SECCOMP = os.path.join(REPO, 'startup', 'rfhs-contestant-seccomp.json')
APPARMOR = os.path.join(REPO, 'misc', 'contestant_apparmor')
OURS = 'rfhs-contestant:'
NAME = 'rfhs-contestant'
# A deny rule wins over any allow rule, and bwrap mounts its sandbox's root
APPARMOR_DROPPED = ['  deny mount,\n']
SYNC = """
To sync them, which keeps the contestants' own rules:
  ./tools/check_contestant_profiles.py --sync
  git diff    # what docker changed: https://github.com/moby/profiles/commits/main
Then run the contestant tests with the new profiles, for example
sudo ./tools/test_contestant_images.sh on an Ubuntu host (or let CI run the
contestant workflows), and commit the result. Until then the contestants
miss docker's newer protections."""


def fetch(path):
    with urllib.request.urlopen(UPSTREAM + path, timeout=60) as response:
        return response.read().decode()


def seccomp_expected(upstream, ours):
    profile = json.loads(upstream)
    profile['syscalls'] += [s for s in ours['syscalls'] if s.get('comment', '').startswith(OURS)]
    return profile


def apparmor_rendered(template_go):
    """apparmor/template.go's profile, from its profile line to before its closing brace."""
    match = re.search(r'const baseTemplate = `(.*?)`', template_go, re.S)
    if not match:
        sys.exit('apparmor/template.go has no baseTemplate any more; update ' + sys.argv[0])
    template = match.group(1)
    body = template[template.index('profile {{.Name}}'):template.rindex('}')]
    # docker adds abstractions/base where it exists, as on every AppArmor host
    inner = ('{\n{{- range $value := .InnerImports}}\n  {{$value}}\n'
             '{{- end}}{{if .InnerImports}}\n{{end}}')
    if inner not in body:
        sys.exit("apparmor/template.go's InnerImports changed; update " + sys.argv[0])
    body = body.replace(inner, '{\n  include <abstractions/base>\n')
    body = body.replace('{{.Name}}', NAME).replace('{{.PeerName}}', NAME)
    # dockerd runs unconfined where it has no profile of its own
    body = body.replace('{{.DaemonProfile}}', 'unconfined')
    if '{{' in body:
        sys.exit('apparmor/template.go has template code this does not render; update ' + sys.argv[0])
    if re.search(r'[$`\\]', body):
        sys.exit('apparmor/template.go now has $, ` or \\, which the unquoted heredoc in '
                 'misc/contestant_apparmor would expand; update ' + sys.argv[0])
    for rule in APPARMOR_DROPPED:
        if rule not in body:
            sys.exit('apparmor/template.go no longer has ' + rule.strip() + '; take it out of '
                     'APPARMOR_DROPPED in ' + sys.argv[0] + ' and the profile')
        body = body.replace(rule, '')
    body = re.sub(r'\n\n\n+', '\n\n', body)
    return body.rstrip() + '\n\n'


def apparmor_split(script):
    """misc/contestant_apparmor around its copy of docker's profile."""
    start = script.index('profile ' + NAME + ' ')
    end = script.index('${userns}\n', start)
    return script[:start], script[start:end], script[end:]


def show(path, ours, new):
    sys.stdout.writelines(difflib.unified_diff(ours.splitlines(True), new.splitlines(True),
                                               path + ' (committed)', path + ' (expected)'))


def main():
    sync = sys.argv[1:] == ['--sync']
    if sys.argv[1:] and not sync:
        sys.exit(__doc__)
    differ = []

    with open(SECCOMP) as f:
        seccomp_ours = json.load(f)
    seccomp_new = seccomp_expected(fetch('seccomp/default.json'), seccomp_ours)
    if seccomp_new != seccomp_ours:
        differ.append('startup/rfhs-contestant-seccomp.json')
        show('startup/rfhs-contestant-seccomp.json', json.dumps(seccomp_ours, indent=1) + '\n',
             json.dumps(seccomp_new, indent=1) + '\n')
        if sync:
            with open(SECCOMP, 'w') as f:
                json.dump(seccomp_new, f, indent='\t')
                f.write('\n')

    with open(APPARMOR) as f:
        script = f.read()
    before, apparmor_ours, after = apparmor_split(script)
    apparmor_new = apparmor_rendered(fetch('apparmor/template.go'))
    if apparmor_new != apparmor_ours:
        differ.append('misc/contestant_apparmor')
        show('misc/contestant_apparmor', apparmor_ours, apparmor_new)
        if sync:
            with open(APPARMOR, 'w') as f:
                f.write(before + apparmor_new + after)

    if not differ:
        print("The contestants' profiles are docker's current defaults plus their own rules")
        return 0
    if sync:
        print('Synced with moby/profiles: ' + ', '.join(differ))
        return 0
    print("These differ from docker's current default profiles in moby/profiles, "
          "plus the contestants' own rules: " + ', '.join(differ))
    print(SYNC)
    return 1


if __name__ == '__main__':
    sys.exit(main())
