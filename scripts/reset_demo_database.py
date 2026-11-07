#!/usr/bin/env python3
"""Fail-closed reset of a provisioned, dedicated CI/Demo application schema.

This is deliberately NOT `supabase db reset`: no Auth/public/storage objects,
arbitrary SQL paths, production target, or credential flags are accepted.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import parse_qsl, unquote, urlsplit

REPOSITORY = "csfishy/taipei-safe-walk-townpass"
ROOT = Path(__file__).resolve().parents[1]
SQL_ROOT = ROOT / "supabase" / "demo"
TARGETS_PATH = SQL_ROOT / "targets.json"
SCHEMA = "safe_walk_demo"
ROLE = "safe_walk_demo_reset"
CI_DATABASE = "safe_walk_ci"
PROTECTED_PROJECT_IDS = frozenset({"gxofnhzkqcmzrftxqddi"})
OWNED_TABLES = frozenset({"helpers", "emergency_alerts", "alert_recipients"})
ALLOWED_TABLES = OWNED_TABLES | {"schema_migrations"}
LOCK_ID = 7289011158462361


class ResetError(RuntimeError):
    """Fixed diagnostics only; never include DSN, SQL or database contents."""


@dataclass(frozen=True)
class Target:
    environment: str
    project_id: str
    dsn: str = field(repr=False)
    host: str


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ResetError(message)


def load_target(environment: str, environ=None, manifest=TARGETS_PATH) -> Target:
    """Validate all configuration before opening a connection."""
    env = os.environ if environ is None else environ
    _require(environment in {"ci", "demo"}, "Only ci/demo resets are permitted.")
    _require(env.get("GITHUB_ACTIONS") == "true", "GitHub Actions context required.")
    _require(env.get("GITHUB_REPOSITORY") == REPOSITORY, "Repository mismatch.")
    _require(env.get("RESET_DATABASE_ENVIRONMENT") == environment,
             "Explicit reset environment is missing or mismatched.")
    project = env.get("RESET_DATABASE_PROJECT_ID", "")
    _require(bool(project), "RESET_DATABASE_PROJECT_ID is required.")
    dsn = env.get("RESET_DATABASE_URL", "")
    _require(bool(dsn), "RESET_DATABASE_URL secret is required.")
    try:
        config = json.loads(Path(manifest).read_text(encoding="utf-8"))
        _require(config["repository"] == REPOSITORY, "Target manifest repository mismatch.")
        protected = set(config["protected_project_ids"]) | PROTECTED_PROJECT_IDS
        entries = config["demo_projects"]
        _require(isinstance(entries, list), "Invalid target manifest.")
        parsed = urlsplit(dsn)
        params = parse_qsl(parsed.query, keep_blank_values=True, strict_parsing=True)
        _require(parsed.scheme in {"postgres", "postgresql"}, "PostgreSQL URI required.")
        _require(parsed.hostname is not None and not parsed.fragment,
                 "Invalid database endpoint.")
        _require(parsed.port == 5432 or (environment == "ci" and parsed.port is not None),
                 "Explicit database port is required; transaction poolers are forbidden.")
        _require(parsed.username is not None and bool(parsed.password),
                 "Dedicated reset role and password are required.")
        _require(len(dict(params)) == len(params), "Duplicate connection parameters forbidden.")
        _require(set(dict(params)) <= {"sslmode", "sslrootcert"},
                 "Unapproved connection parameters forbidden.")
        host = parsed.hostname
        user = unquote(parsed.username)
        database = unquote(parsed.path.removeprefix("/"))
        sslmode = dict(params).get("sslmode")
        _require(project not in protected, "Protected project cannot be reset.")
        if environment == "ci":
            _require(project == "local-ci", "CI project must be local-ci.")
            _require(host in {"127.0.0.1", "localhost", "::1"},
                     "CI must use a runner-local disposable database.")
            _require(database == CI_DATABASE and user == ROLE,
                     "CI database or reset role mismatch.")
            _require(sslmode == "disable", "CI requires explicit loopback SSL configuration.")
        else:
            _require(env.get("GITHUB_EVENT_NAME") in {"push", "workflow_dispatch"}
                     and env.get("GITHUB_REF") == "refs/heads/main",
                     "Demo reset is restricted to main push/manual workflows.")
            _require(re.fullmatch(r"[a-z]{20}", project) is not None,
                     "Invalid Supabase project identifier.")
            matched = [item for item in entries if item["project_id"] == project]
            _require(len(matched) == 1, "Demo project is not uniquely allowlisted.")
            poolers = matched[0]["pooler_hosts"]
            _require(isinstance(poolers, list) and all(
                isinstance(value, str) and re.fullmatch(
                    r"aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com", value)
                for value in poolers), "Invalid pooler allowlist.")
            direct = host == f"db.{project}.supabase.co" and user == ROLE
            pooler = host in poolers and user == f"{ROLE}.{project}"
            _require(direct or pooler, "Demo host/user/project mismatch.")
            _require(database == "postgres", "Unexpected Demo database name.")
            _require(sslmode == "verify-full", "Demo TLS verification is mandatory.")
        return Target(environment, project, dsn, host)
    except ResetError:
        raise
    except (ValueError, TypeError, KeyError, OSError):
        raise ResetError("Invalid target configuration or allowlist.") from None


def _preflight(conn, target: Target) -> None:
    """Check independently provisioned identity and privileges before any DDL/DML."""
    row = conn.execute("""
        SELECT current_database(), current_user, session_user,
               r.rolsuper, r.rolcreatedb, r.rolcreaterole, r.rolbypassrls,
               r.rolreplication, r.oid
        FROM pg_roles r WHERE r.rolname = current_user
    """).fetchone()
    expected_db = CI_DATABASE if target.environment == "ci" else "postgres"
    _require(row is not None and tuple(row[:3]) == (expected_db, ROLE, ROLE),
             "Connected database/session identity mismatch.")
    _require(not any(row[3:8]), "Reset role has forbidden administrative privileges.")
    role_oid = row[8]
    _require(not conn.execute(
        "SELECT 1 FROM pg_auth_members WHERE member = %s", (role_oid,)
    ).fetchone(), "Reset role must not inherit other roles.")
    marker = conn.execute("""
        SELECT environment, project_id, repository FROM safe_walk_demo_control.target
    """).fetchall()
    _require(marker == [(target.environment, target.project_id, REPOSITORY)],
             "Provisioned database environment marker mismatch.")
    marker_acl = conn.execute("""
        SELECT c.relowner <> %s,
          NOT has_table_privilege(current_user, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,TRIGGER'),
          NOT has_schema_privilege(current_user, n.oid, 'CREATE')
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'safe_walk_demo_control' AND c.relname = 'target'
    """, (role_oid,)).fetchone()
    _require(marker_acl is not None and all(marker_acl),
             "Environment marker must be read-only and independently owned.")
    schema = conn.execute(
        "SELECT nspowner = %s FROM pg_namespace WHERE nspname = %s",
        (role_oid, SCHEMA),
    ).fetchone()
    _require(schema == (True,), "Dedicated application schema must be provisioned for reset role.")
    _require(not conn.execute("""
        SELECT 1 FROM pg_namespace n
        WHERE n.nspname <> %s AND n.nspname NOT LIKE 'pg_temp_%%'
          AND n.nspname NOT LIKE 'pg_toast_temp_%%'
          AND (n.nspowner = %s OR has_schema_privilege(current_user, n.oid, 'CREATE'))
        LIMIT 1
    """, (SCHEMA, role_oid)).fetchone(), "Reset role can modify a non-application schema.")
    _require(not conn.execute("""
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname <> %s AND n.nspname NOT LIKE 'pg_%%'
          AND n.nspname <> 'information_schema' AND c.relkind IN ('r','p','v','m','f')
          AND (c.relowner = %s OR has_table_privilege(
              current_user, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,TRIGGER')) LIMIT 1
    """, (SCHEMA, role_oid)).fetchone(), "Reset role can modify non-application data.")
    extension = conn.execute("""
        SELECT n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
        WHERE e.extname='postgis'
    """).fetchone()
    _require(extension == ("extensions",), "PostGIS must be preinstalled in extensions schema.")
    # Third-party event triggers can execute privileged code on migration DDL.
    _require(not conn.execute("SELECT 1 FROM pg_event_trigger WHERE evtenabled <> 'D' LIMIT 1")
             .fetchone(), "Enabled database event triggers require separate safety review.")
    _check_application_objects(conn, role_oid)


def _check_application_objects(conn, role_oid=None) -> None:
    rows = conn.execute("""
        SELECT c.relname, c.relkind, c.relowner = (SELECT oid FROM pg_roles WHERE rolname=current_user)
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=%s AND c.relkind NOT IN ('i','t')
    """, (SCHEMA,)).fetchall()
    _require(all(name in ALLOWED_TABLES and kind == "r" and owned
                 for name, kind, owned in rows), "Unexpected or foreign-owned application objects.")
    _require(not conn.execute("""
        SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=%s AND NOT t.tgisinternal LIMIT 1
    """, (SCHEMA,)).fetchone(), "Application triggers are forbidden during reset.")
    _require(not conn.execute("""
        SELECT 1 FROM pg_constraint k JOIN pg_class t ON t.oid=k.confrelid
        JOIN pg_namespace n ON n.oid=t.relnamespace
        JOIN pg_class source ON source.oid=k.conrelid
        WHERE k.contype='f' AND n.nspname=%s
          AND source.relnamespace <> t.relnamespace LIMIT 1
    """, (SCHEMA,)).fetchone(), "Foreign-schema references prevent isolated reset.")
    _require(not conn.execute("""
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname=%s LIMIT 1
    """, (SCHEMA,)).fetchone(), "RPC functions require separate Level C migration review.")
    # Drift must be rejected BEFORE INSERT/TRUNCATE, not merely rolled back by
    # a later row check. CHECKs, policies, rules and expression indexes can call
    # privileged functions with side effects even on otherwise owned tables.
    contracts = {
        "helpers": {
            "helper_id": ("uuid", True, None),
            "enabled": ("bool", True, "false"),
            "location": ("geography", False, None),
            "updated_at": ("timestamptz", True, "now()"),
        },
        "emergency_alerts": {
            "id": ("uuid", True, "gen_random_uuid()"),
            "sender_id": ("uuid", True, None),
            "location": ("geography", True, None),
            "radius_m": ("int4", True, None),
            "created_at": ("timestamptz", True, "now()"),
        },
        "alert_recipients": {
            "alert_id": ("uuid", True, None),
            "recipient_id": ("uuid", True, None),
            "seen": ("bool", True, "false"),
        },
        "schema_migrations": {
            "version": ("text", True, None), "sha256": ("text", True, None),
        },
    }
    constraints = {
        "helpers": {"PRIMARY KEY (helper_id)"},
        "emergency_alerts": {"PRIMARY KEY (id)",
                             "CHECK (((radius_m >= 50) AND (radius_m <= 3000)))"},
        "alert_recipients": {
            "PRIMARY KEY (alert_id, recipient_id)",
            "FOREIGN KEY (alert_id) REFERENCES safe_walk_demo.emergency_alerts(id) ON DELETE CASCADE",
            "FOREIGN KEY (recipient_id) REFERENCES safe_walk_demo.helpers(helper_id) ON DELETE CASCADE",
        },
        "schema_migrations": {"PRIMARY KEY (version)", "CHECK ((length(sha256) = 64))"},
    }
    for table, _, _ in rows:
        regclass = f"{SCHEMA}.{table}"
        columns = conn.execute("""
            SELECT a.attname, t.typname, a.attnotnull,
                   pg_get_expr(d.adbin, d.adrelid), a.attgenerated, a.attidentity,
                   n.nspname
            FROM pg_attribute a JOIN pg_type t ON t.oid=a.atttypid
            JOIN pg_namespace n ON n.oid=t.typnamespace
            LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
            WHERE a.attrelid=%s::regclass AND a.attnum>0 AND NOT a.attisdropped
        """, (regclass,)).fetchall()
        observed = {name: (kind, required, default) for name, kind, required, default, _, _, _ in columns}
        _require(observed == contracts[table] and all(
            not generated and not identity
            and namespace == ("extensions" if kind == "geography" else "pg_catalog")
            for _, kind, _, _, generated, identity, namespace in columns),
            "Application column/default contract drift requires review.")
        definitions = conn.execute("""
            SELECT pg_get_constraintdef(oid), convalidated, condeferrable
            FROM pg_constraint WHERE conrelid=%s::regclass
        """, (regclass,)).fetchall()
        _require(len(definitions) == len(constraints[table])
                 and {row[0] for row in definitions} == constraints[table]
                 and all(valid and not deferred for _, valid, deferred in definitions),
                 "Application constraint contract drift requires review.")
        _require(not conn.execute("""
            SELECT 1 FROM pg_index WHERE indrelid=%s::regclass
              AND (NOT indisprimary OR indexprs IS NOT NULL OR indpred IS NOT NULL)
        """, (regclass,)).fetchone(), "Unreviewed application indexes are forbidden.")
        _require(not conn.execute(
            "SELECT 1 FROM pg_rewrite WHERE ev_class=%s::regclass", (regclass,)
        ).fetchone(), "Application rules are forbidden during reset.")
        if table in OWNED_TABLES:
            rls = conn.execute("""
                SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid=%s::regclass
            """, (regclass,)).fetchone()
            _require(rls == (True, False) and not conn.execute(
                "SELECT 1 FROM pg_policy WHERE polrelid=%s::regclass", (regclass,)
            ).fetchone(), "Application RLS/policy contract drift requires review.")


def _migrate(conn) -> int:
    files = sorted((SQL_ROOT / "migrations").glob("*.sql"))
    _require(bool(files), "No reviewed Demo migrations found.")
    _require(all(re.fullmatch(r"[0-9]{4}_[a-z0-9_]+\.sql", path.name) for path in files),
             "Invalid migration filename.")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS safe_walk_demo.schema_migrations (
          version text PRIMARY KEY, sha256 text NOT NULL CHECK (length(sha256)=64)
        )
    """)
    applied = dict(conn.execute(
        "SELECT version, sha256 FROM safe_walk_demo.schema_migrations"
    ).fetchall())
    _require(set(applied) <= {path.name for path in files}, "Unrecognized applied migration.")
    for path in files:
        content = path.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        if path.name in applied:
            _require(applied[path.name] == digest, "Applied migration checksum mismatch.")
        else:
            # SQL is reviewed repository code; never accepts a user-supplied SQL path.
            conn.execute(content.decode("utf-8"), prepare=False)
            conn.execute("INSERT INTO safe_walk_demo.schema_migrations VALUES (%s,%s)",
                         (path.name, digest))
    return len(files)


def reset_database(target: Target) -> dict:
    """Atomic reset; independent marker + least privilege protect unrelated data."""
    phase = "connection safety"
    try:
        import psycopg
    except ImportError:
        raise ResetError("Install scripts/requirements-db.txt before database checks.") from None
    try:
        # Prevent ambient libpq settings from changing host, role or search_path.
        forbidden = [key for key in os.environ if key.startswith("PG")
                     and key not in {"PGSSLROOTCERT"}]
        _require(not forbidden, "Ambient PG connection overrides are forbidden.")
        with psycopg.connect(target.dsn, connect_timeout=10, autocommit=False,
                             options="-c statement_timeout=120000 -c lock_timeout=10000") as conn:
            conn.execute("SET LOCAL search_path = pg_catalog")
            conn.execute("SET LOCAL timezone = 'UTC'")
            locked = conn.execute("SELECT pg_try_advisory_xact_lock(%s)", (LOCK_ID,)).fetchone()[0]
            _require(locked, "Another reset owns the database lock; retry after it finishes.")
            phase = "environment and permissions preflight"
            _preflight(conn, target)
            phase = "migrations"
            count = _migrate(conn)
            _check_application_objects(conn)
            phase = "application cleanup"
            conn.execute("""
                TRUNCATE TABLE safe_walk_demo.alert_recipients,
                  safe_walk_demo.emergency_alerts, safe_walk_demo.helpers RESTRICT
            """)
            phase = "synthetic seed"
            conn.execute((SQL_ROOT / "seed.sql").read_text(encoding="utf-8"), prepare=False)
            phase = "schema, seed and permissions verification"
            conn.execute((SQL_ROOT / "verify.sql").read_text(encoding="utf-8"), prepare=False)
            _preflight(conn, target)
        return {"environment": target.environment, "project_id": target.project_id,
                "migrations": count, "tables": len(OWNED_TABLES)}
    except ResetError:
        raise
    except Exception as error:
        code = getattr(error, "sqlstate", None)
        safe_code = code if isinstance(code, str) and re.fullmatch(r"[A-Z0-9]{5}", code) else "unavailable"
        raise ResetError(f"Database reset aborted during {phase} and rolled back (SQLSTATE {safe_code}). "
                         "Check provisioning, migrations and verification; database details redacted.") from None


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True, choices=["ci", "demo"])
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args(argv)
    try:
        target = load_target(args.environment)
        if args.validate_only:
            print("Target configuration validated; no database connection or changes made.")
        else:
            result = reset_database(target)
            print(f"Reset verified: {result['environment']}; {result['migrations']} migrations; "
                  f"{result['tables']} application tables. No Auth/public data reset.")
        return 0
    except ResetError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
