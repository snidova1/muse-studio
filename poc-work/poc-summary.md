# Klaw PoC results (GitHub Actions, run 43462221616, 2026-11-13T16:25:55Z)

Target: Aiven-Open/klaw @ 574ceed2aa5a3d45a5cf000c71088cb42c362b93.
Test instances only (throwaway H2 DBs, throwaway passwords). Nothing
submitted to Bugcrowd, nothing disclosed, nobody contacted.

## CANDIDATE 1 — CONFIRMED
Default Jasypt key kw2021secretkey decrypts the superadmin pwd read
from the live instance's DB; live login with the recovered password
succeeded. Ciphertext: 3GJV973xPMtMXg/wvbANjrJ+oYHoxe6m; recovered: SuperSecret123.

## CANDIDATE 2 — CONFIRMED (after restart)
Import of A's exported admin_config into fresh instance B assigned
WelcomeToKlaw!! to every imported user incl. the superadmin-role
account. Live logins with it failed immediately after import, but
succeeded after restarting B: the in-memory auth manager is populated
at startup, so users imported after boot only become log-in-able after
a restart. Old passwords were rejected in both cases.
Precision: a same-username account pre-seeded on B is NOT overwritten
(insertIntoUsers refuses duplicates) — B used a different seeded admin
(admin2) so the imported superadmin was a new user.

Checks passed: 12, failed: 2. Full log: poc-results.log.
