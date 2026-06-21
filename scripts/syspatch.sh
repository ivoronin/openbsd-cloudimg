#!/bin/ksh
# Converge on "no errata missing". syspatch's apply exit codes are overloaded
# and version-dependent - a self-update ("run it again"), a kernel relink in
# progress, and "nothing to do" can share a code - so we do NOT key off them.
#
# `syspatch -c` lists the still-missing errata on stdout (empty when up to
# date) and is the authority. Unlike apply, it is not blocked while
# reorder_kernel relinks the kernel after first boot: syspatch only guards the
# bare/-R/-r forms with that check, not -c. So the loop is: ask what's missing,
# apply, repeat until nothing is missing - riding through self-update and the
# relink, and failing loudly rather than shipping an unpatched image.
n=0
while :; do
	n=$((n + 1))
	if [ "$n" -ge 60 ]; then
		echo "syspatch did not converge after $n passes" >&2
		exit 1
	fi
	missing=$(syspatch -c) || { sleep 15; continue; }  # mirror/verify hiccup: retry
	[ -z "$missing" ] && exit 0                         # nothing missing: done
	syspatch || sleep 15                                # apply; refused mid-relink: wait
done
