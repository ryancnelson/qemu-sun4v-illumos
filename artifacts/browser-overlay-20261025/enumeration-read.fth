\ OWNER INTERACTIVE; do not paste whole file. STOP at each CHECK.
hex
dev /pci@1f,0/pci@1,1/ide@3
ls
\ CHECK expected ide@0 child exists; otherwise STOP.
dev /pci@1f,0/pci@1,1/ide@3/ide@0
ls
\ CHECK disk@0 enumerated; otherwise STOP. No alias fallback.
device-end
800 alloc-mem dup . constant s3buf
\ CHECK nonzero buffer.
" /pci@1f,0/pci@1,1/ide@3/ide@0/disk@0" open-dev dup . constant s3h
\ CHECK nonzero handle.
0 0 " seek" s3h $call-method .
\ CHECK 0.
s3buf 40 " read" s3h $call-method .
\ CHECK 40 HEX.
s3buf 40 dump
\ CHECK exact64 bytes for requested offset0 via frozen verifier BEFORE next command.
800 0 " seek" s3h $call-method .
\ CHECK 0.
s3buf 40 " read" s3h $call-method .
\ CHECK 40 HEX.
s3buf 40 dump
\ CHECK exact64 bytes for requested offset0x800; otherwise STOP.
s3h close-dev
\ CHECK normal prompt.
s3buf 800 free-mem
\ CHECK normal prompt. WRITE NOT TESTED; no boot.
