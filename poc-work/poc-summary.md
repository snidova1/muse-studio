# Klaw PoC results (GitHub Actions, run 43446490808, 2026-11-13T14:52:14Z)

Target: Aiven-Open/klaw @ 574ceed2aa5a3d45a5cf000c71088cb42c362b93.
Test instances only (throwaway H2 DBs, throwaway passwords). Nothing
submitted to Bugcrowd, nothing disclosed, nobody contacted.

## CANDIDATE 1 — CONFIRMED
Default Jasypt key kw2021secretkey decrypts the superadmin pwd read
from the live instance's DB; live login with the recovered password
succeeded. Ciphertext: L4lp4RioV6LsNsi9vzL2GH0HO9aqSneT; recovered: SuperSecret123.

## CANDIDATE 2 — NOT CONFIRMED (2 check(s) failed)
The live logins with WelcomeToKlaw!! on B did NOT all succeed — see
poc-results.log and the C2 diagnostic (export pwd decryption + B user
table) for what was actually imported and stored.
Precision: a same-username account pre-seeded on B is NOT overwritten
(insertIntoUsers refuses duplicates) — B used a different seeded admin
(admin2) so the imported superadmin was a new user.

Checks passed: 9, failed: 2. Full log: poc-results.log.
