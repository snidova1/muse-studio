# Klaw PoC results (GitHub Actions, run 43429674588, 2026-11-13T13:01:14Z)

Target: Aiven-Open/klaw @ 574ceed2aa5a3d45a5cf000c71088cb42c362b93.
Test instances only (throwaway H2 DBs, throwaway passwords). Nothing
submitted to Bugcrowd, nothing disclosed, nobody contacted.

## CANDIDATE 1 — CONFIRMED
Default Jasypt key kw2021secretkey decrypts the superadmin pwd read
from the live instance's DB; live login with the recovered password
succeeded. Ciphertext: XHfzcvDvaGuROZuaTwTsZJ/lZChLiL3I; recovered: SuperSecret123.

## CANDIDATE 2 — NOT CONFIRMED (2 check(s) failed)
Import of A's exported admin_config into fresh instance B assigned
WelcomeToKlaw!! to every imported user incl. the superadmin-role
account; live logins with it succeeded, old passwords rejected.
Precision: a same-username account pre-seeded on B is NOT overwritten
(insertIntoUsers refuses duplicates) — B used a different seeded admin
(admin2) so the imported superadmin was a new user.

Checks passed: 9, failed: 2. Full log: poc-results.log.
