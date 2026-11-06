import os, sqlite3, sys, tempfile, shutil, time, subprocess
mode = sys.argv[1]
work = tempfile.mkdtemp(prefix="vacprobe2-", dir="/private/tmp/claude-501/dd/vac")
tmp = os.path.join(work, "tmp"); os.makedirs(tmp)
os.environ["TMPDIR"] = tmp; os.environ["SQLITE_TMPDIR"] = tmp
db = os.path.join(work, "j.store")
c = sqlite3.connect(db); c.execute("PRAGMA journal_mode=WAL"); c.execute("CREATE TABLE e(id INTEGER PRIMARY KEY, body TEXT)")
c.executemany("INSERT INTO e(body) VALUES (?)", (("y"*900 + str(i),) for i in range(500000)))  # ~470 MB, nothing deleted: the copy is as big as the file
c.commit(); c.execute("PRAGMA wal_checkpoint(TRUNCATE)"); c.close()
print(mode, "db bytes", os.path.getsize(db))
code = f"""
import sqlite3,os,sys,time
os.environ['TMPDIR']='{tmp}'; os.environ['SQLITE_TMPDIR']='{tmp}'
c=sqlite3.connect('{db}', isolation_level=None)
{'c.execute("PRAGMA temp_store=MEMORY")' if mode=='memory' else ''}
c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
t=time.time(); c.execute('VACUUM'); print('vacuum', round(time.time()-t,2),'s', flush=True)
"""
p = subprocess.Popen(["/usr/bin/python3", "-c", code], stdout=subprocess.PIPE, text=True)
hits = set(); maxrss = 0
while p.poll() is None:
    out = subprocess.run(["lsof", "-p", str(p.pid)], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if tmp in line or "etilqs" in line or "(deleted)" in line.lower():
            hits.add(" ".join(line.split()[3:5] + [line.split()[-1]]))
    rss = subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)], capture_output=True, text=True).stdout.strip()
    if rss: maxrss = max(maxrss, int(rss))
    time.sleep(0.05)
print(p.stdout.read().strip(), "| max RSS MB", maxrss // 1024)
print("temp-file handles seen:", sorted(hits)[:6])
print("tmp dir listing after:", os.listdir(tmp))
shutil.rmtree(work)
