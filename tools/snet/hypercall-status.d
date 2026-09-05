#!/usr/sbin/dtrace -s
/* Generate traffic in another shell. Negative values are raw HV errors. */
#pragma D option quiet

fbt:snet:snet_hcall*:entry
{
    self->write = arg1;
}

fbt:snet:snet_hcall*:return
{
    @returns[self->write, (int64_t)arg1] = count();
    self->write = 0;
}

tick-10sec
{
    exit(0);
}

END
{
    printa("write=%d return=%d count=%@d\n", @returns);
}
