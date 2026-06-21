#!/bin/ksh
# Keep applying errata until syspatch reports there is nothing left, which is
# the only unambiguous "done": exit 2. A single run stops early in two cases we
# must ride through, and exit 0 does not tell them apart from "all applied":
#   - it exits 0 after patching syspatch itself ("updated itself, run it
#     again") with patches still missing - e.g. 001_syspatch is the first
#     errata on a release;
#   - it exits non-zero while reorder_kernel relinks the kernel after first
#     boot.
# So loop on exit 0 (made progress, run again), retry anything else (relink in
# progress or transient), and only stop on exit 2. Cap to fail loudly rather
# than ship an unpatched image.
n=0
while :; do
	n=$((n + 1))
	if [ "$n" -ge 60 ]; then
		echo "syspatch did not converge after $n runs" >&2
		exit 1
	fi
	syspatch
	case $? in
	2) exit 0 ;;     # nothing left to apply -> done
	0) ;;            # applied something (maybe just self-update) -> run again
	*) sleep 15 ;;   # reorder_kernel relinking or transient error -> retry
	esac
done
