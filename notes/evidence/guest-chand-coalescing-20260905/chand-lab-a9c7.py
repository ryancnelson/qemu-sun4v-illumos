import importlib.util, io, json, pathlib, shlex, subprocess, sys, tarfile, time

ROOT = pathlib.Path('/Volumes/T9/ryan-homedir/devel/niagra-qemu-solaris-project')
LAB = '/var/tmp/chand-coalesce-a9c7'
SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', 'teddeck']
INNER = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '-o',
         'ProxyCommand=docker exec -i openindiana-sparc64 socat - TCP:10.0.5.15:22',
         '-i', '.ssh/id_rsa', 'root@10.0.5.15']

def guest(command, data=None, timeout=120):
    return subprocess.run(SSH + [shlex.join(INNER + [command])], input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=timeout, check=True).stdout

spec = importlib.util.spec_from_file_location('chan', ROOT/'tools/chan/host-chan.py')
host = importlib.util.module_from_spec(spec); spec.loader.exec_module(host)
CONFIG = json.dumps(host.C)

def peer_command(mode):
    return SSH + [shlex.join(['docker','exec','openindiana-sparc64','python3',
                  '/tmp/chand-peer-a9c7.py',mode,CONFIG])]

def peer(mode):
    return subprocess.check_output(peer_command(mode), timeout=130).decode()

if sys.argv[1] == 'stage':
    files = {'baseline.c': subprocess.check_output(['git','show','HEAD:tools/chan/guest-chand.c'], cwd=ROOT),
             'candidate.c': (ROOT/'tools/chan/guest-chand.c').read_bytes(),
             'chan.h': (ROOT/'tools/chan/chan.h').read_bytes()}
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w') as tar:
        for name, content in files.items():
            item = tarfile.TarInfo(name); item.size = len(content)
            tar.addfile(item, io.BytesIO(content))
    print(guest('mkdir '+LAB+' && cd '+LAB+' && tar xf -', buf.getvalue()).decode())
    print(guest('cd '+LAB+' && /jack/gcc13 -O2 -Wall -Wextra -o baseline baseline.c -lsocket -lnsl && /jack/gcc13 -O2 -Wall -Wextra -o candidate candidate.c -lsocket -lnsl && file baseline candidate && digest -a sha256 baseline candidate', timeout=240).decode())
elif sys.argv[1] == 'guest':
    print(guest(sys.argv[2]).decode())
elif sys.argv[1] == 'prepare-peer':
    subprocess.run(SSH+["docker exec -i openindiana-sparc64 sh -c 'cat > /tmp/chand-peer-a9c7.py'"],
        input=pathlib.Path('/private/tmp/chand-peer-a9c7.py').read_bytes(),check=True)
    print(peer('init'))
elif sys.argv[1] == 'restore':
    print(peer('restore'))
elif sys.argv[1] == 'bench':
    variant = sys.argv[2]
    assert variant in ('baseline','candidate')
    print(peer('reset'), flush=True)
    command = ('NIAG_CHAN_DEV=/dev/rdsk/c1d0s2 NIAG_CHAN_GUEST_BLK=640 nohup '+
        LAB+'/'+variant+' 2 '+LAB+'/socket </dev/null >'+LAB+'/'+variant+'.log 2>&1 & echo $!')
    pid = int(guest(command).decode().strip())
    print('daemon pid',pid,flush=True)
    tracer = None
    receiver = None
    try:
        probe = ('fbt:hsimd:hsimd_strategy:entry /pid == '+str(pid)+'/ '+
          '{ self->t=timestamp; self->sz=((struct buf *)arg0)->b_bcount; '+
          'self->op=(((struct buf *)arg0)->b_flags & 0x40) != 0; '+
          '@calls[self->op,self->sz]=count(); } '+
          'fbt:hsimd:hsimd_strategy:return /self->t/ '+
          '{ @avg_us[self->op,self->sz]=avg((timestamp-self->t)/1000); '+
          '@max_us[self->op,self->sz]=max((timestamp-self->t)/1000); self->t=0; } '+
          'tick-90sec { exit(0); } '+
          'END { printf("CALLS op size count\\n"); printa(@calls); '+
          'printf("AVG_US op size us\\n"); printa(@avg_us); '+
          'printf("MAX_US op size us\\n"); printa(@max_us); }')
        command = ('nohup dtrace -n '+shlex.quote(probe)+' >'+LAB+'/'+variant+'.dtrace 2>&1 </dev/null & echo $!')
        tracer = int(guest(command).decode().strip())
        ready = ('i=0; while ! grep -q "matched .* probes" '+LAB+'/'+variant+'.dtrace; '+
            'do i=$((i+1)); if [ "$i" -ge 45 ]; then cat '+LAB+'/'+variant+'.dtrace; exit 1; fi; '+
            'sleep 1; done; head -2 '+LAB+'/'+variant+'.dtrace')
        print(guest(ready, timeout=65).decode(), flush=True)
        receiver = subprocess.Popen(peer_command('receive'),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        perl = ('use IO::Socket::UNIX; use Time::HiRes qw(usleep); '+
            'my $s=IO::Socket::UNIX->new(Peer=>"'+LAB+'/socket",Type=>SOCK_STREAM) or die $!; '+
            'my $b="p" x 6144; for (1..512) { my $o=0; while($o<length($b)) '+
            '{ my $n=syswrite($s,$b,length($b)-$o,$o); defined($n) && $n>0 or die $!; $o+=$n; } '+
            'usleep(1000); } shutdown($s,1); close($s);')
        print(guest('/usr/bin/perl -e '+shlex.quote(perl),timeout=130).decode(),flush=True)
        out, err = receiver.communicate(timeout=130)
        if receiver.returncode:
            raise RuntimeError(err.decode())
        print(out.decode(),flush=True)
        pathlib.Path('/private/tmp/'+variant+'-a9c7.json').write_bytes(out)
    finally:
        if receiver and receiver.poll() is None:
            receiver.terminate(); receiver.wait(timeout=5)
        if tracer:
            stop = ('kill -TERM '+str(tracer)+'; i=0; while kill -0 '+str(tracer)+' 2>/dev/null; '+
                'do i=$((i+1)); [ "$i" -lt 15 ] || exit 1; sleep 1; done')
            print(guest(stop).decode(),flush=True)
        print(guest('kill -TERM '+str(pid)).decode(),flush=True)
        if tracer:
            trace = guest('cat '+LAB+'/'+variant+'.dtrace')
            pathlib.Path('/private/tmp/'+variant+'-a9c7.dtrace').write_bytes(trace)
            print(trace.decode(),flush=True)
