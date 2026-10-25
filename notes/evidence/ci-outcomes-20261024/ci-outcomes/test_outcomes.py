#!/usr/bin/env python3
import pathlib, subprocess, json, hashlib, sys, os, tempfile
P=pathlib.Path(__file__).resolve().parent
label=sys.argv[1] if len(sys.argv)>1 else "candidate"
script=P/label/"ci-openbios-sun4u-boot.sh"
s=script.read_text()
def func(name):
    a=s.index(name+"() {")
    b=s.index("\n}",a)+2
    return s[a:b]
out=pathlib.Path(tempfile.mkdtemp(prefix="results-"+label+"-",dir=P))
print("RUN_DIR",out)
common=r"""
set -euo pipefail
run_dir=$1
console_log=$run_dir/console.log
container=fixture-only
keep_guest=0
preserve_ready=0
docker() {
    printf '%s\n' "$*" >>"$run_dir/docker-calls.log"
    case "$1" in
    inspect)
        if [[ "$*" == *--format* ]]; then
            if [[ "$STATE" == ERROR ]]; then return 1; fi
            if [[ "$*" == *OOMKilled* ]]; then printf '%s\n' "$STATE"
            elif [[ "$STATE" == "true false 137" || "$STATE" == "false false 137" ]]; then echo false
            else echo true; fi
        else printf '[{"State":{"fixture":"%s"}}]\n' "$STATE"; fi ;;
    logs) echo 'fixture Docker logs' ;;
    stop|rm) : ;;
    esac
}
sleep() { :; }
"""
candidate=label=="candidate"
h=common
if candidate:h+='source "'+str(P/"candidate/console-outcomes.sh")+'"\ncontainer_created=1\n'
h+=func("wait_for_console")+"\n"
cases=[
("normal","prompt.log","false true 0",0,None),
("panic","panic-prompt.log","false true 0",20,"PANIC"),
("maintenance","maintenance-prompt.log","false true 0",21,"MAINTENANCE"),
("actual-run136","run136-console.log","false true 0",21,"MAINTENANCE"),
("oom-stale-prompt","prompt.log","true false 137",22,"HOST_OOM"),
("timeout","booting.log","false true 0",23,"TIMEOUT"),
("exit137-not-oom","prompt.log","false false 137",25,"CONTAINER_EXITED"),
("inspect-error","prompt.log","ERROR",26,"INSPECT_ERROR"),
("malformed-state","prompt.log","invalid",26,"INSPECT_ERROR"),
("oom-plus-panic","panic-prompt.log","true false 137",22,"HOST_OOM"),
]
failed=[]
for name,fixture,state,code,kind in cases:
    d=out/name;d.mkdir(exist_ok=True)
    (d/"console.log").write_bytes((P/"fixtures"/fixture).read_bytes())
    pattern="Configuring devices." if name=="actual-run136" else "ready"
    run=h+'wait_for_console "'+pattern+'" 0\n'
    (d/"executed.sh").write_text(run)
    r=subprocess.run(["bash",str(d/"executed.sh"),str(d)],env=dict(os.environ,STATE=state),capture_output=True,text=True,timeout=15)
    (d/"stdout.log").write_text(r.stdout);(d/"stderr.log").write_text(r.stderr)
    okay=r.returncode==code
    if candidate and kind:
        okay &= (d/"outcome.env").exists() and ("SUN4U_OUTCOME="+kind) in (d/"outcome.env").read_text()
        okay &= (d/"container-inspect-final.json").exists() and (d/"console-final.log").exists()
    print("PASS" if okay else "FAIL",name,"expected",code,kind,"actual",r.returncode)
    if not okay:failed.append(name)
if candidate:
    # Actual signal and EXIT traps exercise evidence capture before destructive cleanup.
    for signal,code in [("TERM",143),("INT",130),("HUP",129)]:
        d=out/("cancel-"+signal);d.mkdir(exist_ok=True);(d/"console.log").write_text("booting\n")
        run=h+func("cleanup")+"""
trap 'finalize_run $?' EXIT
trap 'cancel_run 130' INT
trap 'cancel_run 143' TERM
trap 'cancel_run 129' HUP
kill -SIGNAL $$
""".replace("SIGNAL",signal)
        (d/"executed.sh").write_text(run)
        r=subprocess.run(["bash",str(d/"executed.sh"),str(d)],env=dict(os.environ,STATE="false true 0"),capture_output=True,text=True,timeout=15)
        (d/"stdout.log").write_text(r.stdout);(d/"stderr.log").write_text(r.stderr)
        calls=(d/"docker-calls.log").read_text()
        okay=r.returncode==code and "SUN4U_OUTCOME=CANCELLED" in (d/"outcome.env").read_text() and calls.index("inspect")<calls.index("stop")
        print("PASS" if okay else "FAIL","cancel-"+signal,"actual",r.returncode)
        if not okay:failed.append("cancel-"+signal)

    # Run the entire candidate harness with command-level fixtures. No Docker
    # executable is invoked; every external resource command is a shell function.
    success="""Welcome to OpenBIOS v1.1
0 >
/pci@1f,0/pci@1,1/ebus@1/su@14,3f8 ok
To select the keyboard layout
To select the language you wish to use
pcipsy0 is /pci@1f,0
ebus0 is /pci@1f,0/pci@1,1/ebus@1
su0 is /pci@1f,0/pci@1,1/ebus@1/su@14,3f8
User selected: English
Configuring devices.
"""
    (P/"fixtures/full-success.log").write_text(success)
    full=r"""
set -euo pipefail
fixture_root=$1
fixture_run=$2
fixture_case=$3
fixture_script=$4
docker() {
 printf '%s\n' "$*" >>"$fixture_root/full-docker-calls.log"
 case "$1" in
 image) echo sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f ;;
 run)
   if [[ "$*" == *sha256sum* ]]; then echo '902dc13a3dbc23a6057cd8f98109632fcbf11ad80a2ad6e0934f48b8b8305d40  qemu'
   elif [[ "$*" == *qemu-img* ]]; then
     for arg in "$@"; do
       if [[ "$arg" == type=bind,src=*,dst=/target ]]; then
         target="${arg#type=bind,src=}"; target="${target%,dst=/target}"
         echo fixture-disk >"$target/install.qcow2"
       fi
     done
   else cp "$fixture_root/input.log" "$fixture_run/console.log"; echo fixture-id; fi ;;
 inspect)
   if [[ "$*" == *--format* ]]; then
     n=$(cat "$fixture_root/polls" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" >"$fixture_root/polls"
     if [[ "$fixture_case" == observe-maintenance && "$n" -ge 7 ]]; then echo 'Requesting System Maintenance Mode' >>"$fixture_run/console.log"; fi
     if [[ "$fixture_case" == oom ]]; then echo 'true false 137'; else echo 'false true 0'; fi
   else echo '[{"State":{"Running":true,"OOMKilled":false}}]'; fi ;;
 logs) echo fixture-logs ;;
 stop|rm) : ;;
 esac
}
sha256sum() { if [[ "$*" == *-c* ]]; then cat >/dev/null; else echo fixture-hash; fi; }
stat() { echo 123; }
socat() { cat >/dev/null; }
sleep() { :; }
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 99999999 0 99999999 0%% /\n'; }
# All harness control flow is real; Docker, filesystem-capacity and transport
# observations are fixtures, including a tiny fake qcow2 output.
source "$fixture_script" "$fixture_root/firmware" "$fixture_run"
"""
    for name,code,kind in [("normal",0,"PASS"),("maintenance",21,"MAINTENANCE"),("oom",22,"HOST_OOM"),("observe-maintenance",21,"MAINTENANCE"),("preserve-healthy",0,"PASS")]:
        d=out/("full-"+name);d.mkdir(exist_ok=True)
        (d/"input.log").write_text(success+("Requesting System Maintenance Mode\n" if name=="maintenance" else ""))
        (d/"firmware").write_text("fixture");(d/"iso").write_text("fixture")
        run=d/"run"
        # The entire result root is new for every invocation; retain all earlier
        # poll counters, command logs and outcome files as immutable evidence.
        assert not run.exists()
        (d/"executed.sh").write_text(full)
        r=subprocess.run(["bash",str(d/"executed.sh"),str(d),str(run),name,str(script)],env=dict(os.environ,B134_ISO=str(d/"iso"),SUN4U_INSTALL_TARGET_GIB="4" if name in ("observe-maintenance","preserve-healthy") else "0",SUN4U_KEEP_GUEST="1" if name in ("observe-maintenance","preserve-healthy") else "0",SUN4U_INSTALL_OBSERVE_SECONDS="2"),capture_output=True,text=True,timeout=15)
        (d/"stdout.log").write_text(r.stdout);(d/"stderr.log").write_text(r.stderr)
        okay=r.returncode==code and (run/"outcome.env").exists() and ("SUN4U_OUTCOME="+kind) in (run/"outcome.env").read_text()
        calls=(d/"full-docker-calls.log").read_text()
        okay &= (("stop -t 5" in calls) == (name!="preserve-healthy")) and "container-inspect-final.json" in str(list(run.iterdir()))
        if name=="observe-maintenance":
            okay &= "SUN4U_OPENBIOS_BOOT=PASS" in r.stdout
            okay &= "SUN4U_INSTALLER_OBSERVATION=RECORDED_NOT_INSTALLATION_PROVEN" not in r.stdout
            okay &= r.stdout.find("SUN4U_OPENBIOS_BOOT=PASS") < r.stdout.find("SUN4U_OUTCOME=MAINTENANCE")
            okay &= (d/"polls").read_text().strip()=="7"
        if name=="preserve-healthy":
            okay &= "INTERACTIVE_GUEST_PRESERVED=" in r.stdout and "SUN4U_OUTCOME=PASS" in r.stdout
        print("PASS" if okay else "FAIL","full-"+name,"actual",r.returncode)
        if not okay:failed.append("full-"+name)

print("RESULT",len(cases)+(8 if candidate else 0)-len(failed),"passed",len(failed),"failed")
(out/"summary.json").write_text(json.dumps({"passed":len(cases)+(8 if candidate else 0)-len(failed),"failed":failed,"script_sha256":hashlib.sha256(s.encode()).hexdigest(),"test_sha256":hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()},indent=2)+"\n")
sys.exit(bool(failed))
