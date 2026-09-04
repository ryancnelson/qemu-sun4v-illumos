#!/usr/sbin/dtrace -qs

#pragma D option quiet

dtrace:::BEGIN
{
	printf("NIAGARA_HOST_DTRACE=START pid=%d\n", $target);
}

pid$target::cpu_exec:entry
{
	@cpu_exec_by_lwp[tid] = count();
}

pid$target::cpu_interrupt:entry
{
	@cpu_interrupt_by_lwp[tid] = count();
}

pid$target::qemu_cpu_kick:entry
{
	@cpu_kick_by_lwp[tid] = count();
}

pid$target::async_run_on_cpu:entry,
pid$target::async_safe_run_on_cpu:entry
{
	@async_on_cpu_by_lwp[probefunc, tid] = count();
}

profile:::tick-10sec
{
	printf("\nNIAGARA_HOST_DTRACE=SNAPSHOT timestamp=%Y\n", walltimestamp);
	printa("cpu_exec lwp=%d count=%@d\n", @cpu_exec_by_lwp);
	printa("cpu_interrupt lwp=%d count=%@d\n", @cpu_interrupt_by_lwp);
	printa("cpu_kick lwp=%d count=%@d\n", @cpu_kick_by_lwp);
	printa("async_on_cpu function=%s lwp=%d count=%@d\n",
	    @async_on_cpu_by_lwp);
}

dtrace:::END
{
	printf("\nNIAGARA_HOST_DTRACE=END timestamp=%Y\n", walltimestamp);
	printa("cpu_exec lwp=%d count=%@d\n", @cpu_exec_by_lwp);
	printa("cpu_interrupt lwp=%d count=%@d\n", @cpu_interrupt_by_lwp);
	printa("cpu_kick lwp=%d count=%@d\n", @cpu_kick_by_lwp);
	printa("async_on_cpu function=%s lwp=%d count=%@d\n",
	    @async_on_cpu_by_lwp);
}
