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


def fetch_data():
    conn = get_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT username, created_at, ttl_seconds "
            "FROM secret_log ORDER BY created_at DESC"
        )
        return cur.fetchall()
    finally:
        conn.close()


@app.route("/")
def index():
    error = None
    rows = []

    try:
        rows = fetch_data()
    except Exception as exc:
        error = str(exc)

    latest = None
    if rows:
        username, created_at, ttl_seconds = rows[0]
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        expires_at = created_at + timedelta(seconds=ttl_seconds)
        latest = {
            "username": username,
            "created_at": created_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
            "ttl_seconds": ttl_seconds,
            "expires_at": expires_at.isoformat(),
        }

    all_rows = []
    for username, created_at, ttl_seconds in rows:
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        expires_at = created_at + timedelta(seconds=ttl_seconds)
        all_rows.append({
            "username": username,
            "created_at": created_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
            "ttl_seconds": ttl_seconds,
            "expires_at_iso": expires_at.isoformat(),
        })

    return render_template(
        "index.html",
        latest=latest,
        all_rows=all_rows,
        error=error,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
