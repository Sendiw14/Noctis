import os, sqlite3, sys, threading, time, tempfile, shutil
mode = sys.argv[1]  # default | memory
work = tempfile.mkdtemp(prefix="vacprobe-", dir="/private/tmp/claude-501/dd/vac")
tmp = os.path.join(work, "tmp"); os.makedirs(tmp)
os.environ["TMPDIR"] = tmp; os.environ["SQLITE_TMPDIR"] = tmp
db = os.path.join(work, "j.store")
c = sqlite3.connect(db); c.execute("PRAGMA journal_mode=WAL")
c.execute("CREATE TABLE e(id INTEGER PRIMARY KEY, body TEXT)")
c.executemany("INSERT INTO e(body) VALUES (?)", (("x"*900 + str(i),) for i in range(120000)))
c.commit(); c.execute("DELETE FROM e WHERE id % 10 <> 0"); c.commit(); c.execute("PRAGMA wal_checkpoint(TRUNCATE)"); c.close()
print("sqlite", sqlite3.sqlite_version, "lib", sqlite3.sqlite3.__file__ if hasattr(sqlite3,'sqlite3') else "")
size0 = os.path.getsize(db)
opts = [r[0] for r in sqlite3.connect(":memory:").execute("PRAGMA compile_options") if "TEMP" in r[0]]
print("compile options:", opts)
seen = {}
stop = False
def poll():
    while not stop:
        for root, _, files in os.walk(work):
            for f in files:
                p = os.path.join(root, f)
                if p == db: continue
                try: seen[p.replace(work, "")] = max(seen.get(p.replace(work, ""), 0), os.path.getsize(p))
                except OSError: pass
        time.sleep(0.002)
t = threading.Thread(target=poll); t.start()
c = sqlite3.connect(db, isolation_level=None)
if mode == "memory": c.execute("PRAGMA temp_store=MEMORY")
t0 = time.time(); c.execute("VACUUM"); dt = time.time() - t0
stop = True; t.join(); c.close()
print(mode, "vacuum %.3fs" % dt, "size %d -> %d" % (size0, os.path.getsize(db)))
print("files seen besides the db during vacuum (path: max bytes):", seen)
print("tmp dir used:", any(k.startswith("/tmp/") for k in seen))
shutil.rmtree(work)
