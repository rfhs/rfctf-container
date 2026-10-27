#!/bin/sh
# Benchmarks the docker healthcheck of running containers, and measures each
# container's baseline (idle) CPU.
#   ./tools/bench_healthcheck.sh [-n runs] [-w seconds] [-t ms] [-c checker]
#     [-x command] [-s setup] [-f] container...
# It runs each container's healthcheck as docker does: the image's
# HEALTHCHECK, CMD as is and CMD-SHELL with /bin/sh -c, or the shell command
# -x. -c copies a checker into the containers and runs it in place of that
# command's program. -s runs a shell command in each container once it is
# healthy, before the runs, and -f expects the healthcheck to fail from then
# on, to measure a degraded container. -t fails if a container's median
# checker time is over ms. The containers have to be started with
# --no-healthcheck. Needs cgroup v2 and read access to the containers'
# cgroups. Under GitHub Actions the report also goes to the job summary.
set -eu

runs=10
window=15
limit=""
checker=""
command=""
setup=""
expect_fail=""
while getopts n:w:t:c:x:s:f opt; do
  case "${opt}" in
    n) runs="${OPTARG}";;
    w) window="${OPTARG}";;
    t) limit="${OPTARG}";;
    c) checker="${OPTARG}";;
    x) command="${OPTARG}";;
    s) setup="${OPTARG}";;
    f) expect_fail=1;;
    *) exit 2;;
  esac
done
shift $((OPTIND - 1))
if [ "$#" -eq 0 ]; then
  printf 'usage: %s [-n runs] [-w seconds] [-t ms] [-c checker] [-x command] [-s setup] [-f] container...\n' "${0}" >&2
  exit 2
fi

# docker's own runs of the healthcheck would land in the windows
for c in "$@"; do
  case "$(docker inspect -f '{{if .Config.Healthcheck}}{{index .Config.Healthcheck.Test 0}}{{end}}' "${c}")" in
    '' | NONE) ;;
    *)
      printf '%s runs docker'"'"'s healthcheck, which would land in the windows: start it with --no-healthcheck\n' "${c}" >&2
      exit 2
      ;;
  esac
done

cgroups=""
for c in "$@"; do
  id="$(docker inspect -f '{{.Id}}' "${c}")"
  for dir in "/sys/fs/cgroup/docker/${id}" "/sys/fs/cgroup/system.slice/docker-${id}.scope"; do
    if [ -r "${dir}/cpu.stat" ]; then
      cgroups="${cgroups} ${dir}"
      continue 2
    fi
  done
  printf 'No cgroup v2 cpu.stat found for %s\n' "${c}" >&2
  exit 1
done

# not in /tmp, which docker's --tmpfs mounts noexec
bench_dir=/healthcheck-bench
bench_checker="${bench_dir}/checker"
quiet="${bench_dir}/quiet"
t="$(mktemp -d)"
containers="$*"
trap 'for c in ${containers}; do docker exec "${c}" rm -rf "${bench_dir}" > /dev/null 2>&1 || true; done
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -s "${t}/report" ]; then
    { echo "~~~"; cat "${t}/report"; echo "~~~"; } >> "${GITHUB_STEP_SUMMARY}"
  fi
  rm -rf "${t}"' EXIT

report() {
  printf '%s\n' "${1}" | tee -a "${t}/report"
}

# Each container's command goes in ${t}/cmd.<container>: for CMD one argument
# per line, for CMD-SHELL the shell command; ${t}/kind.<container> says which
for c in "$@"; do
  if [ -n "${command}" ]; then
    echo CMD-SHELL > "${t}/kind.${c}"
    printf '%s\n' "${command}" > "${t}/cmd.${c}"
  else
    docker image inspect -f '{{if .Config.Healthcheck}}{{range .Config.Healthcheck.Test}}{{println .}}{{end}}{{end}}' \
      "$(docker inspect -f '{{.Image}}' "${c}")" > "${t}/test"
    kind="$(head -n 1 "${t}/test")"
    case "${kind}" in
      CMD | CMD-SHELL) ;;
      *)
        printf '%s'"'"'s image has no healthcheck; give one with -x\n' "${c}" >&2
        exit 2
        ;;
    esac
    echo "${kind}" > "${t}/kind.${c}"
    sed 1d "${t}/test" > "${t}/cmd.${c}"
  fi
  if [ -n "${checker}" ]; then
    docker exec -i "${c}" sh -c 'mkdir -p "${1%/*}" && cat > "$1" && chmod +x "$1"' sh "${bench_checker}" < "${checker}"
    sed -i "1s|^[[:space:]]*[^[:space:]]*|${bench_checker}|" "${t}/cmd.${c}"
  fi
done

# Runs the healthcheck in a container and prints its output, then a line
# "bench <unit> <start> <end> <exit status>", timed in the container: in ns
# from date's %N, or in s to 10 ms from /proc/uptime where date has no %N, as
# in busybox. The host does the arithmetic, which is 32-bit in mksh.
# BENCH_PATH goes first in PATH.
# shellcheck disable=SC2016
timed='if [ -n "${BENCH_PATH:-}" ]; then PATH="${BENCH_PATH}:${PATH}"; fi
t0=$(date +%s%N)
case "${t0}" in
  *N | ??????????)
    read -r t0 _ < /proc/uptime; "$@"; rc=$?; read -r t1 _ < /proc/uptime; unit=s ;;
  *) "$@"; rc=$?; t1=$(date +%s%N); unit=ns ;;
esac
printf "\nbench %s %s %s %s\n" "${unit}" "${t0}" "${t1}" "${rc}"
exit "${rc}"'

check_in() {
  read -r kind < "${t}/kind.${1}"
  if [ "${kind}" = CMD-SHELL ]; then
    set -- "${1}" /bin/sh -c "$(cat "${t}/cmd.${1}")"
  else
    set -- "${1}"
    while IFS= read -r arg; do
      set -- "$@" "${arg}"
    done < "${t}/cmd.${1}"
  fi
  in_c="${1}"
  shift
  docker exec -e "BENCH_PATH=${bench_path:-}" "${in_c}" sh -c "${timed}" sh "$@"
}

cpu_usec() {
  for dir in ${cgroups}; do
    awk '$1 == "usage_usec" { print $2 }' "${dir}/cpu.stat"
  done
}

# ms since the bench started, small enough for mksh's 32-bit arithmetic
bench_start="$(date +%s)"
now_ms() {
  date +%s%N | awk -v s="${bench_start}" '{ printf "%.0f\n", (length($1) > 10 ? $1 / 1000000 : $1 * 1000) - s * 1000 }'
}

# Runs in the containers: "start" snapshots every process's CPU, "end
# seconds" prints the ten that used the most since then, with the children
# they waited for. stat's second field, the name, can hold spaces and ")".
cat > "${t}/procs.sh" << 'EOF'
dir=/healthcheck-bench/procs
snapshot() {
  for p in /proc/[0-9]*; do
    if read -r line 2> /dev/null < "${p}/stat"; then
      printf '%s\n' "${line}"
    fi
  done
}
if [ "${1}" = start ]; then
  mkdir -p "${dir}"
  snapshot > "${dir}/start"
  exit 0
fi
snapshot > "${dir}/end"
awk -v tck="$(getconf CLK_TCK 2> /dev/null || echo 100)" -v secs="${2}" '
  { name = $0; sub(/^[^(]*\(/, "", name); sub(/\) [^)]*$/, "", name)
    rest = $0; sub(/^.*\) /, "", rest); split(rest, f, " ")
    key = $1 " " f[20]; ticks = f[12] + f[13] + f[14] + f[15] }
  FNR == NR { start[key] = ticks; next }
  { used = ticks - (key in start ? start[key] : 0)
    if (used > 0) printf "%.2f %s %s\n", used * 100 / tck / secs, $1, name }
' "${dir}/start" "${dir}/end" | sort -rn | head -n 10 | while read -r pct pid name; do
  cmdline="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2> /dev/null | cut -c 1-120)"
  printf '%7s%%  %s\n' "${pct}" "${cmdline:-[${name}]}"
done
rm -rf "${dir}"
EOF

report "host: $(nproc) CPUs, kernel $(uname -r), docker $(docker version --format '{{.Server.Version}}')"
for c in "$@"; do
  read -r kind < "${t}/kind.${c}"
  if [ "${kind}" = CMD-SHELL ]; then
    report "${c} ($(docker inspect -f '{{.Config.Image}}' "${c}")): /bin/sh -c $(cat "${t}/cmd.${c}")"
  else
    report "${c} ($(docker inspect -f '{{.Config.Image}}' "${c}")): $(tr '\n' ' ' < "${t}/cmd.${c}")"
  fi
done

# Healthy is what docker means by it: the healthcheck passed once. The checks
# run with a notify-send that does nothing, so the contestant images' popups
# for a failing pass and then Recovered don't land in the first windows.
for c in "$@"; do
  docker exec "${c}" sh -c 'mkdir -p "$1" && printf "#!/bin/sh\n" > "$1/notify-send" && chmod +x "$1/notify-send"' sh "${quiet}"
done
deadline=$(($(now_ms) + 300000))
pending="$*"
bench_path="${quiet}"
while [ -n "${pending}" ]; do
  waiting=""
  for c in ${pending}; do
    if check_in "${c}" > "${t}/wait.${c}" 2>&1; then
      # as 2026-10-26 11:41:44, which busybox date can read too
      started="$(docker inspect -f '{{.State.StartedAt}}' "${c}")"
      started="${started%%.*}"
      started="${started%Z}"
      started="$(date -u -d "${started%%T*} ${started#*T}" +%s)"
      report "${c} is healthy; it started $(awk -v s="${started}" -v n="$(date +%s)" 'BEGIN { print n - s }') s ago"
    else
      waiting="${waiting} ${c}"
    fi
  done
  pending="${waiting# }"
  if [ -n "${pending}" ]; then
    if [ "$(now_ms)" -ge "${deadline}" ]; then
      for c in ${pending}; do
        report "${c} did not become healthy in 300 s; its last check said:"
        sed -e '/^bench [a-z]* [0-9.]* [0-9.]* [0-9]*$/d' -e 's/^/  /' "${t}/wait.${c}" | tee -a "${t}/report"
      done
      exit 1
    fi
    sleep 5
  fi
done
bench_path=""

if [ -n "${setup}" ]; then
  for c in "$@"; do
    if ! docker exec "${c}" sh -c "${setup}" > "${t}/setup.${c}" 2>&1; then
      report "The setup failed in ${c}:"
      sed 's/^/  /' "${t}/setup.${c}" | tee -a "${t}/report"
      exit 1
    fi
    report "${c}: ran the setup: ${setup}"
  done
fi

# The containers run the healthcheck at the same time, the worst case for
# several containers on one host. Each run is an idle window, which gives the
# baseline, followed by a window that starts with the healthcheck; its CPU is
# the difference.
for c in "$@"; do
  docker exec -i "${c}" sh -s start < "${t}/procs.sh"
done
procs_start="$(now_ms)"
for run in $(seq "${runs}"); do
  cpu_usec > "${t}/idle0"
  sleep "${window}"
  cpu_usec > "${t}/idle1"
  start="$(now_ms)"
  cpu_usec > "${t}/run0"
  for c in "$@"; do
    (
      check_in "${c}" > "${t}/out.${c}" 2>&1 || true
      echo "$(($(now_ms) - start))" > "${t}/exec.${c}"
    ) &
  done
  wait
  elapsed=$(($(now_ms) - start))
  if [ "${elapsed}" -lt $((window * 1000)) ]; then
    sleep "$(awk -v ms=$((window * 1000 - elapsed)) 'BEGIN { print ms / 1000 }')"
  fi
  cpu_usec > "${t}/run1"
  i=1
  for c in "$@"; do
    exec_ms="$(cat "${t}/exec.${c}")"
    tag=""
    read -r tag unit t0 t1 rc << EOF
$(tail -n 1 "${t}/out.${c}")
EOF
    checker_ms=""
    if [ "${tag}" = bench ]; then
      checker_ms="$(awk -v u="${unit}" -v a="${t0}" -v b="${t1}" 'BEGIN { printf "%.0f", (u == "ns" ? (b - a) / 1000000 : (b - a) * 1000) }')"
    fi
    read -r checker_cpu idle_pct << EOF
$(paste "${t}/idle0" "${t}/idle1" "${t}/run0" "${t}/run1" | awk -v i="${i}" -v w="${window}" \
  'NR == i { idle = $2 - $1; printf "%d %.2f\n", int(($4 - $3 - idle) / 1000), idle / (w * 10000) }')
EOF
    line="run ${run}/${runs} ${c}: exec ${exec_ms} ms, checker ${checker_ms:-?} ms, checker CPU ${checker_cpu} ms, idle ${idle_pct}% of a core"
    bad=0
    if [ "${tag}" != bench ]; then
      checker_ms="${exec_ms}"
      rc=255
      bad=1
      line="${line}, FAILED (docker exec failed)"
    elif [ -n "${expect_fail}" ] && [ "${rc}" -eq 0 ]; then
      bad=1
      line="${line}, PASSED but -f expects it to fail"
    elif [ -z "${expect_fail}" ] && [ "${rc}" -ne 0 ]; then
      bad=1
      line="${line}, FAILED (exit ${rc})"
    fi
    report "${line}"
    if [ "${bad}" -ne 0 ]; then
      sed -e '/^bench [a-z]* [0-9.]* [0-9.]* [0-9]*$/d' -e 's/^/  /' "${t}/out.${c}" | tee -a "${t}/report"
    fi
    echo "${c} ${exec_ms} ${checker_ms} ${checker_cpu} ${idle_pct} ${bad}" >> "${t}/results"
    i=$((i + 1))
  done
done
procs_secs="$(awk -v ms=$(($(now_ms) - procs_start)) 'BEGIN { print ms / 1000 }')"

median() {
  sort -n | awk '{ v[NR] = $1 } END { if (NR % 2) print v[(NR + 1) / 2]; else print (v[NR / 2] + v[NR / 2 + 1]) / 2 }'
}

status=0
report ""
report "$(printf '%-24s %8s %11s %15s %22s %9s' container 'exec ms' 'checker ms' 'checker CPU ms' 'idle % (min-max)' 'bad runs')"
for c in "$@"; do
  awk -v c="${c}" '$1 == c' "${t}/results" > "${t}/r"
  checker_ms="$(awk '{ print $3 }' "${t}/r" | median)"
  bad="$(awk '$6 != 0 { n++ } END { print n + 0 }' "${t}/r")"
  report "$(printf '%-24s %8s %11s %15s %22s %9s' "${c}" \
    "$(awk '{ print $2 }' "${t}/r" | median)" "${checker_ms}" "$(awk '{ print $4 }' "${t}/r" | median)" \
    "$(awk '{ print $5 }' "${t}/r" | median) ($(awk '{ print $5 }' "${t}/r" | sort -n | head -n 1)-$(awk '{ print $5 }' "${t}/r" | sort -n | tail -n 1))" \
    "${bad}")"
  if [ "${bad}" -ne 0 ]; then
    status=1
  fi
  if [ -n "${limit}" ] && awk -v m="${checker_ms}" -v l="${limit}" 'BEGIN { exit !(m > l) }'; then
    over="${over:-}
${c}: the median checker time, ${checker_ms} ms, is over the ${limit} ms limit"
    status=1
  fi
done
for c in "$@"; do
  report ""
  report "Top processes in ${c}, % of one CPU over the ${procs_secs} s of the runs:"
  docker exec -i "${c}" sh -s end "${procs_secs}" < "${t}/procs.sh" 2>&1 | tee -a "${t}/report" || true
done
report "
Medians of ${runs} runs. exec is docker exec running the healthcheck, as
docker runs it; checker is the healthcheck itself, timed in the container.
idle is the container's baseline CPU, in the ${window} s before each run, as a
percentage of one CPU; checker CPU is the container's CPU in the ${window} s
after the healthcheck started, less that baseline. Bad runs failed, or with
-f passed. The top processes count the children they waited for; the
healthcheck isn't among them, as docker exec starts it from outside the
container."
if [ -n "${over:-}" ]; then
  report "${over}"
fi
exit "${status}"
