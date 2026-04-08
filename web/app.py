import os
from datetime import datetime, timezone, timedelta

import psycopg2
from flask import Flask, render_template

app = Flask(__name__)


def get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
    )


def fetch_latest():
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT username, created_at, ttl_seconds "
            "FROM secret_log ORDER BY created_at DESC LIMIT 1"
        )
        return cur.fetchone()
    finally:
        conn.close()


@app.route("/")
def index():
    error = None
    row = None

    try:
        row = fetch_latest()
    except Exception as exc:
        error = str(exc)

    if row:
        username, created_at, ttl_seconds = row
        # Ensure timezone-aware datetime
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        expires_at = created_at + timedelta(seconds=ttl_seconds)
        return render_template(
            "index.html",
            username=username,
            created_at=created_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
            ttl_seconds=ttl_seconds,
            expires_at=expires_at.isoformat(),
            has_data=True,
            error=None,
        )

    return render_template(
        "index.html",
        has_data=False,
        error=error,
        username=None,
        created_at=None,
        ttl_seconds=None,
        expires_at=None,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
