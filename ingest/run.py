"""Run every adapter and write ingest/out/records.json for the Node importer.

Each adapter is isolated: one failing source never stops the others, and its
failure is reported rather than hidden.
"""
from __future__ import annotations

import json
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

import aicte_internships
import ias
import nicsi
import isro
import nsp
from common import Blocked, Fetcher

ADAPTERS = [nsp, nicsi, isro, ias, aicte_internships]
OUT = Path(__file__).parent / "out"


def main() -> int:
    OUT.mkdir(exist_ok=True)
    now = datetime.now(timezone.utc)
    fetcher = Fetcher()
    records, sources = [], []
    for mod in ADAPTERS:
        sid = mod.SOURCE_ID
        try:
            recs, msg = mod.run(fetcher, now)
            records.extend(recs)
            sources.append({"id": sid, "status": "ok", "count": len(recs), "message": msg})
        except (Blocked, getattr(mod, "Skipped", Blocked)) as e:
            sources.append({"id": sid, "status": "skipped", "count": 0, "message": str(e)})
        except Exception as e:  # noqa: BLE001 - report and continue
            traceback.print_exc(file=sys.stderr)
            sources.append({"id": sid, "status": "error", "count": 0, "message": f"{type(e).__name__}: {e}"})
    payload = {"generatedAt": now.isoformat(), "sources": sources, "records": records}
    (OUT / "records.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    for s in sources:
        print(f"[{s['status']:7}] {s['id']:18} {s['count']:3}  {s['message']}")
    print(f"total records: {len(records)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
