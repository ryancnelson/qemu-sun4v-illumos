#!/usr/bin/env python3
import ast,pathlib,tempfile,subprocess,os,time,signal,json,hashlib
P=pathlib.Path(__file__).resolve().parent
F=P.parent/"ci-outcomes"
source=ast.parse((F/"test_outcomes.py").read_text())
success=next(n.value.value for n in ast.walk(source) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=="success" for t in n.targets) and isinstance(n.value,ast.Constant))
out=pathlib.Path(tempfile.mkdtemp(prefix="validation-",dir=P))
print("RESULT_DIR",out)
shell=r"""
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
"""
cases=[
# name, console addition, keep-maintenance, expected code/outcome/preservation
("normal","",0,0,"PASS",False),
("healthy-keep-maintenance-alone","",1,0,"PASS",False),
("maintenance-late-oom","Requesting System Maintenance Mode\n",1,22,"HOST_OOM",False),
("maintenance-late-stopped","Requesting System Maintenance Mode\n",1,25,"CONTAINER_EXITED",False),
("maintenance-final-health-fails","Requesting System Maintenance Mode\n",1,26,"INSPECT_ERROR",False),
("maintenance-default","Requesting System Maintenance Mode\n",0,21,"MAINTENANCE",False),
("maintenance-optin","Requesting System Maintenance Mode\n",1,21,"MAINTENANCE",True),
("maintenance-panic","Requesting System Maintenance Mode\npanic - simultaneous\n",1,20,"PANIC",False),
("maintenance-oom","Requesting System Maintenance Mode\n",1,22,"HOST_OOM",False),
("maintenance-stopped","Requesting System Maintenance Mode\n",1,25,"CONTAINER_EXITED",False),
("maintenance-late-panic","Requesting System Maintenance Mode\n",1,20,"PANIC",False),
("late-panic-main","",0,20,"PANIC",False),
("late-panic-final","",0,20,"PANIC",False),
("evidence-inspect-fails","",0,0,"PASS",False),
("evidence-logs-fail","",0,0,"PASS",False),
("maintenance-evidence-fails","Requesting System Maintenance Mode\n",1,21,"MAINTENANCE",True),
("final-health-fails","",1,26,"INSPECT_ERROR",False),
("outcome-file-failure","panic - primary failure\n",0,20,"PANIC",False),
("cancel-final-pass","",1,143,"CANCELLED",False),
("cancel-maintenance","Requesting System Maintenance Mode\n",1,143,"CANCELLED",False),
("cancel-create-cid","",1,143,"CANCELLED",False),
("cancel-create-stdout","",1,143,"CANCELLED",False),
("create-failed-unrelated","",1,125,"HARNESS_ERROR",False),
]
results=[]
for name,addition,keep,expected,kind,preserve in cases:
 d=out/name;d.mkdir()
 (d/"input.log").write_text(success+addition)
 (d/"firmware").write_text("fixture");(d/"iso").write_text("fixture");(d/"executed.sh").write_text(shell)
 env=dict(os.environ,B134_ISO=str(d/"iso"),SUN4U_INSTALL_TARGET_GIB="0",SUN4U_KEEP_GUEST="0",SUN4U_KEEP_MAINTENANCE=str(keep))
 args=["bash",str(d/"executed.sh"),str(d),str(d/"run"),name,str(P/"candidate/ci-openbios-sun4u-boot.sh")]
 proc=subprocess.Popen(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 if name in ("cancel-final-pass","cancel-maintenance"):
  deadline=time.monotonic()+5
  while not (d/"ready-to-signal").exists():
   if proc.poll() is not None or time.monotonic()>deadline:raise RuntimeError("signal handshake failed "+name)
   time.sleep(.01)
  os.kill(proc.pid,signal.SIGTERM);(d/"release").touch()
 stdout,stderr=proc.communicate(timeout=10)
 (d/"stdout.log").write_text(stdout);(d/"stderr.log").write_text(stderr)
 calls=(d/"docker-calls.log").read_text()
 statusfile=d/"run/outcome.env"
 actual=statusfile.read_text() if statusfile.is_file() else None
 wanted="SUN4U_OUTCOME="+kind
 ok=proc.returncode==expected and stdout.count("SUN4U_OUTCOME=")==1 and wanted in stdout
 if name!="outcome-file-failure":ok &= actual==wanted+"\nEXIT_CODE="+str(expected)+"\n"
 else:ok &= "Final outcome file unavailable" in stderr
 didstop="stop -t 5 " in calls
 ok &= didstop==(not preserve and name!="create-failed-unrelated")
 ok &= ("MAINTENANCE_GUEST_PRESERVED=" in stdout)==preserve
 if name.startswith("cancel-create"):
  ok &= (d/"run/container-inspect-final.json").is_file() and ("stop -t 5 "+"a"*64) in calls
 if name=="late-panic-final":
  ok &= "SUN4U_OPENBIOS_BOOT=PASS" in stdout and "panic -" in (d/"run/console-final.log").read_text()
 if name in ("evidence-inspect-fails","evidence-logs-fail","maintenance-evidence-fails"):
  ok &= (d/"run/console-final.log").is_file() and "unavailable" in stderr
 results.append({"name":name,"passed":bool(ok),"expected":expected,"actual":proc.returncode,"outcome":actual,"preserved":preserve,"stopped":didstop})
 print("PASS" if ok else "FAIL",name,"exit",proc.returncode)

for filename in ("owned-container.cid","container-id.txt"):
 d=out/("stale-"+filename);d.mkdir();(d/"run").mkdir()
 (d/"run"/filename).write_text("b"*64+"\n")
 for name0,text0 in [("input.log",success),("firmware","fixture"),("iso","fixture"),("executed.sh",shell)]:(d/name0).write_text(text0)
 r=subprocess.run(["bash",str(d/"executed.sh"),str(d),str(d/"run"),"normal",str(P/"candidate/ci-openbios-sun4u-boot.sh")],env=dict(os.environ,B134_ISO=str(d/"iso"),SUN4U_INSTALL_TARGET_GIB="0",SUN4U_KEEP_GUEST="0",SUN4U_KEEP_MAINTENANCE="1"),capture_output=True,text=True,timeout=10)
 (d/"stdout.log").write_text(r.stdout);(d/"stderr.log").write_text(r.stderr)
 calls=(d/"docker-calls.log").read_text()
 ok=r.returncode==1 and "stop " not in calls and "run -d " not in calls and not (d/"run/outcome.env").exists()
 results.append({"name":"stale-"+filename,"passed":ok,"actual":r.returncode})
 print("PASS" if ok else "FAIL","stale-"+filename)
(out/"summary.json").write_text(json.dumps(results,indent=2)+"\n")
print("RESULT",sum(x["passed"] for x in results),"/",len(results))
raise SystemExit(not all(x["passed"] for x in results))
