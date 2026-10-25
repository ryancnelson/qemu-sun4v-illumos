\ OWNER INTERACTIVE: one block at a time; NEVER paste whole file.
\ Every CHECK is a hard external gate; stop on any mismatch/error/trap.
hex
800 alloc-mem dup . constant s2buf
\ CHECK buffer nonzero; otherwise STOP.
" /pci@1f,0/pci@1,1/ide@3/ide@0/cdrom@0" open-dev dup . constant s2h1
\ CHECK handle nonzero; otherwise STOP.
\ BLOCK A requested absolute offset 0x0; length 0x40 (64 decimal).
0 0 " seek" s2h1 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block A at REQUESTED offset; otherwise STOP.
\ BLOCK B requested absolute offset 0x100; length 0x40 (64 decimal).
100 0 " seek" s2h1 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block B at REQUESTED offset; otherwise STOP.
\ BLOCK C requested absolute offset 0x7e0; length 0x40 (64 decimal).
7e0 0 " seek" s2h1 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block C at REQUESTED offset; otherwise STOP.
\ BLOCK D requested absolute offset 0x820; length 0x40 (64 decimal).
\ NO SEEK: successful C advanced position from 0x7e0 to 0x820.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block D at REQUESTED offset; otherwise STOP.
s2h1 close-dev
\ CHECK normal prompt, no error; first handle is now closed.
" /pci@1f,0/pci@1,1/ide@3/ide@0/cdrom@0" open-dev dup . constant s2h2
\ CHECK new handle nonzero; may numerically equal old handle.
\ BLOCK E requested absolute offset 0x800; length 0x40 (64 decimal).
800 0 " seek" s2h2 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h2 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block E at REQUESTED offset; otherwise STOP.
\ BLOCK F requested absolute offset 0x7fc0; length 0x40 (64 decimal).
7fc0 0 " seek" s2h2 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h2 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block F at REQUESTED offset; otherwise STOP.
s2h2 close-dev
\ CHECK normal prompt, no error.
s2buf 800 free-mem
\ END storage control only; no boot command.
