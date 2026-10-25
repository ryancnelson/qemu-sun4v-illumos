
set -euo pipefail
fixture_root=$1
fixture_run=$2
fixture_case=$3
fixture_script=$4
fake_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
docker() {
 printf '%s\n' "$*" >>"$fixture_root/docker-calls.log"
 case "$1" in
 image) echo sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f ;;
 run)
   if [[ "$*" == *sha256sum* ]]; then echo '902dc13a3dbc23a6057cd8f98109632fcbf11ad80a2ad6e0934f48b8b8305d40  qemu'
   elif [[ "$fixture_case" == create-failed-unrelated ]]; then return 125
   else
     cp "$fixture_root/input.log" "$fixture_run/console.log"
     echo "$fake_id"
     # Emulate Docker's ownership record unless probing stdout-only recovery.
     if [[ "$fixture_case" != cancel-create-stdout ]]; then echo "$fake_id" >"$fixture_run/owned-container.cid"; fi
     if [[ "$fixture_case" == outcome-file-failure ]]; then mkdir "$fixture_run/outcome.env"; fi
     if [[ "$fixture_case" == cancel-create* ]]; then kill -TERM $$; fi
   fi ;;
 inspect)
   if [[ "$*" == *--format* ]]; then
     n=$(cat "$fixture_root/polls" 2>/dev/null || echo 0);n=$((n+1));echo "$n" >"$fixture_root/polls"
     case "$fixture_case" in
       maintenance-late-oom) if ((n>1));then echo 'true false 137';else echo 'false true 0';fi ;;
       maintenance-late-stopped) if ((n>1));then echo 'false false 1';else echo 'false true 0';fi ;;
       *oom*) echo 'true false 137' ;;
       *stopped*) echo 'false false 1' ;;
       final-health-fails|maintenance-final-health-fails)
         if [[ -f "$fixture_root/final-inspect" ]]; then echo 'fixture inspect unavailable' >&2;return 1;fi
         echo 'false true 0' ;;
       *) echo 'false true 0' ;;
     esac
   else
     n=$(cat "$fixture_root/raw-inspects" 2>/dev/null || echo 0);n=$((n+1));echo "$n" >"$fixture_root/raw-inspects"
     # Failure paths enter final inspect first; successes have a main inspect first.
     case "$fixture_case" in
       late-panic-main) echo 'panic - injected after last wait' >>"$fixture_run/console.log" ;;
       late-panic-final) if ((n==2));then echo 'panic - injected during final capture' >>"$fixture_run/console.log";fi ;;
       maintenance-late-panic) echo 'panic - diagnostic state became panic' >>"$fixture_run/console.log" ;;
     esac
     if ((n==2)) || [[ "$fixture_case" == maintenance* ]]; then : >"$fixture_root/final-inspect";fi
     if [[ "$fixture_case" == cancel-final-pass && "$n" == 2 || "$fixture_case" == cancel-maintenance ]]; then
       : >"$fixture_root/ready-to-signal"
       while [[ ! -f "$fixture_root/release" ]];do sleep 0.01;done
     fi
     if [[ "$fixture_case" == evidence-inspect-fails && "$n" == 2 || "$fixture_case" == maintenance-evidence-fails ]]; then
       echo 'fixture raw inspect unavailable' >&2;return 1
     fi
     echo '[{"State":{"Running":true,"OOMKilled":false}}]'
   fi ;;
 logs)
   if [[ "$fixture_case" == evidence-logs-fail || "$fixture_case" == maintenance-evidence-fails ]];then echo 'fixture logs unavailable' >&2;return 1;fi
   echo fixture-logs ;;
 stop|rm) : ;;
 esac
}
sha256sum() { if [[ "$*" == *-c* ]];then cat >/dev/null;else echo fixture-hash;fi; }
stat() { echo 123; }
socat() { cat >/dev/null; }
# Keep real short sleeps only for the signal handshake inside inspect.
source "$fixture_script" "$fixture_root/firmware" "$fixture_run"
