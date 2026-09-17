# Stadium 2 decomp cross-check, 2026-09-17

Reference: https://github.com/michiiik/pokestadiumgs at
`2b44e8fa04aba7ba70493d1ad909cea481517394`,
`src/fragments/79/fragment79_3C60B0.c`.

This corrects the earlier timer interpretation in lifecycle-families.md and
lifecycle-rendering.md. The earlier audit inverted the spawn windows and
mistook direct -1 returns for arguments passed into the update helper.

| Family | Spawn cadence after init | Direct termination |
| --- | --- | --- |
| 2 | Every 3 ticks below 1770 (last spawn 1767) | 1801 |
| 4, 6, 21 | Every 7 ticks below 120 (last spawn 119) | 181 |

These correspond to primary Swift, Bind/Wrap/Constrict, String Shot/Spider Web,
and Disable routes. Existing slots update during the drain interval. The
callback returns before calling the shared update helper at termination.
Counters use signed 16-bit wrap, matching the native sh/lh sequence.

Verification reads the actual US ROM instructions at each callback's +20,
+24, +30, +34 and +38 offsets (hex): termination comparison, branch-likely,
-1 return value, spawn-window comparison and skip-spawn branch. Unit tests
exercise all four cadence windows and expiration boundaries.

This fixes lifecycle scheduling; it does not implement the missing geometry
kernels. Several remain GLOBAL_ASM in the new fork, including 84163B4C and
84165CC0. Do not count these four families as newly renderable.
