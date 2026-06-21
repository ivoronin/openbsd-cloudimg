#!/bin/ksh
# Apply errata without detecting the kernel relink ourselves (that means
# fragile process-name matching). syspatch is the authority: it refuses with a
# non-zero exit while reorder_kernel relinks the kernel after first boot, and
# also exits non-zero right after patching itself ("run it again"). So retry:
#   0 = applied, 2 = nothing left  -> done
#   anything else = relink in progress, self-update, or a real error -> retry,
#   giving up loudly after enough tries so we never ship an unpatched image.
i=0
while :; do
	syspatch
	case $? in
	0|2) exit 0 ;;
	*)   i=$((i + 1))
	     [ "$i" -ge 40 ] && { echo "syspatch failed after $i attempts" >&2; exit 1; }
	     sleep 15 ;;
	esac
done
