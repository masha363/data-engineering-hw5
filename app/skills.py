import csv
import io
import json
import os
import re
import resource
import sys
import time
from collections import Counter
from datetime import datetime
from itertools import combinations
from math import comb

ROLES = {
    "Аналитик",
    "BI-аналитик, аналитик данных",
    "Бизнес-аналитик",
    "Системный аналитик",
    "Продуктовый аналитик",
}

S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "http://rustfs:9000")
S3_KEY = os.environ.get("S3_ACCESS_KEY", "rustfsadmin")
S3_SECRET = os.environ.get("S3_SECRET_KEY", "rustfsadmin")
BUCKET = os.environ.get("BUCKET", "hh-lake")
OBJECT = os.environ.get("OBJECT", "raw/hh_analysts_2024.csv")
RUN = os.environ.get("RUN", "k8s")
PARTS = int(os.environ.get("PARTS", "4"))
BOUNDARY = re.compile(rb"\nhh,\d+,")
HW3 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hw3")

csv.field_size_limit(10**9)


def log(msg):
    print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} {msg}", flush=True)


def cgroup_peak_mb():
    for path in ("/sys/fs/cgroup/memory.peak", "/sys/fs/cgroup/memory/memory.max_usage_in_bytes"):
        try:
            with open(path) as f:
                return int(f.read()) / 2**20
        except OSError:
            pass
    return None


def report_memory():
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    cg = cgroup_peak_mb()
    log(f"PEAK_RSS_MB={rss:.1f}")
    log(f"CGROUP_PEAK_MB={cg:.1f} (память контейнера вместе со страничным кэшем)" if cg else "CGROUP_PEAK_MB=нет данных")


def s3():
    import boto3
    from botocore.config import Config
    return boto3.client(
        "s3",
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_KEY,
        aws_secret_access_key=S3_SECRET,
        region_name="us-east-1",
        config=Config(
            s3={"addressing_style": "path"},
            request_checksum_calculation="when_required",
            response_checksum_validation="when_required",
            retries={"max_attempts": 10},
        ),
    )


def parse_skills(raw):
    if not raw:
        return []
    return sorted({s.strip(" ") for s in raw.split(";")} - {""})


class Counts:
    def __init__(self):
        self.rows = 0
        self.variant = 0
        self.hist = Counter()
        self.k1 = Counter()
        self.k2 = Counter()

    def add_rows(self, reader, header):
        i_role = header.index("role")
        i_skills = header.index("key_skills")
        for r in reader:
            if r == header:
                continue
            self.rows += 1
            if r[i_role] not in ROLES:
                continue
            self.variant += 1
            skills = parse_skills(r[i_skills])
            self.hist[len(skills)] += 1
            self.k1.update(skills)
            self.k2.update(combinations(skills, 2))

    def to_json(self):
        return {
            "rows": self.rows,
            "variant": self.variant,
            "hist": dict(self.hist),
            "k1": dict(self.k1),
            "k2": [[a, b, c] for (a, b), c in self.k2.items()],
        }

    def merge_json(self, part):
        self.rows += part["rows"]
        self.variant += part["variant"]
        self.hist.update({int(n): c for n, c in part["hist"].items()})
        self.k1.update(part["k1"])
        self.k2.update({(a, b): c for a, b, c in part["k2"]})

    def summary(self):
        return {
            "rows_in_object": self.rows,
            "variant_vacancies": self.variant,
            "with_skills": sum(c for n, c in self.hist.items() if n > 0),
            "skills_hist": {str(n): self.hist[n] for n in sorted(self.hist)},
            "distinct": [len(self.k1), len(self.k2)],
            "total": [sum(self.k1.values()), sum(self.k2.values())],
            "expected_total_triples_sum_C(n,3)": sum(comb(n, 3) * c for n, c in self.hist.items()),
        }


def sorted_rows(counter):
    rows = [((key,) if isinstance(key, str) else key) + (c,) for key, c in counter.items()]
    rows.sort(key=lambda r: (-r[-1], r[:-1]))
    return rows


def load_hw3_table(name):
    table = {}
    with open(os.path.join(HW3, name), encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        for r in reader:
            key = r[0] if len(r) == 2 else tuple(r[:-1])
            table[key] = int(r[-1])
    return table


def compare_with_hw3(counts):
    summary = counts.summary()
    with open(os.path.join(HW3, "summary.json"), encoding="utf-8") as f:
        hw3 = json.load(f)
    checks = [
        ("вакансий варианта", summary["variant_vacancies"], hw3["variant_vacancies"]),
        ("с навыками", summary["with_skills"], hw3["with_skills"]),
        ("навыков уникальных", summary["distinct"][0], hw3["distinct"][0]),
        ("навыков вхождений", summary["total"][0], hw3["total"][0]),
        ("пар уникальных", summary["distinct"][1], hw3["distinct"][1]),
        ("пар вхождений", summary["total"][1], hw3["total"][1]),
        ("троек вхождений (сумма C(n,3))", summary["expected_total_triples_sum_C(n,3)"], hw3["total"][2]),
        ("распределение числа навыков", summary["skills_hist"], hw3["skills_hist"]),
    ]
    ok = True
    for name, mine, theirs in checks:
        same = mine == theirs
        ok = ok and same
        shown = "по всем n" if isinstance(mine, dict) else f"{mine} / {theirs}"
        log(f"  {name:<32} {shown:<20} {'да' if same else 'НЕТ'}")
    for name, mine, path in (("k1", counts.k1, "k1_skills.csv"), ("k2", counts.k2, "k2_pairs.csv")):
        theirs = load_hw3_table(path)
        diff = sum(1 for key in set(mine) | set(theirs) if mine.get(key) != theirs.get(key))
        ok = ok and diff == 0
        log(f"  таблица {name}: строк {len(mine)} / {len(theirs)}, расхождений {diff}")
    hw3_top = sorted_rows(Counter(load_hw3_table("k2_pairs.csv")))[:10]
    my_top = sorted_rows(counts.k2)[:10]
    same_top = hw3_top == my_top
    ok = ok and same_top
    log("топ-10 пар навыков:")
    for i, (a, b, c) in enumerate(my_top, 1):
        log(f"  {i:>2}. {a} + {b}: {c}")
    log(f"топ-10 совпадает с ДЗ 3: {'да' if same_top else 'НЕТ'}")
    log(f"сверка с ДЗ 3: {'ВСЁ СОВПАЛО' if ok else 'ЕСТЬ РАСХОЖДЕНИЯ'}")
    return ok


def run_local(path):
    t0 = time.time()
    log(f"режим local: читаю {path} ({os.path.getsize(path) / 2**20:.1f} МБ)")
    counts = Counts()
    with open(path, encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        counts.add_rows(reader, header)
    s = counts.summary()
    log(f"строк {s['rows_in_object']}, вакансий варианта {s['variant_vacancies']}, пар уникальных {s['distinct'][1]}, вхождений {s['total'][1]}")
    compare_with_hw3(counts)
    log(f"время расчёта {time.time() - t0:.2f} с")
    report_memory()


def run_upload(path):
    client = s3()
    buckets = [b["Name"] for b in client.list_buckets().get("Buckets", [])]
    if BUCKET not in buckets:
        client.create_bucket(Bucket=BUCKET)
        log(f"создан бакет {BUCKET}")
    t0 = time.time()
    client.upload_file(path, BUCKET, OBJECT)
    head = client.head_object(Bucket=BUCKET, Key=OBJECT)
    log(f"загружено s3://{BUCKET}/{OBJECT}: {head['ContentLength']} байт за {time.time() - t0:.1f} с, ETag {head['ETag']}")
    log(f"объекты в бакете: {[o['Key'] for o in client.list_objects_v2(Bucket=BUCKET).get('Contents', [])]}")


def get_range(client, start, end):
    return client.get_object(Bucket=BUCKET, Key=OBJECT, Range=f"bytes={start}-{end - 1}")["Body"].read()


def run_part():
    t0 = time.time()
    index = int(os.environ["JOB_COMPLETION_INDEX"])
    client = s3()
    size = client.head_object(Bucket=BUCKET, Key=OBJECT)["ContentLength"]
    step = size // PARTS
    start = index * step
    end = size if index == PARTS - 1 else (index + 1) * step
    tail = 0 if end == size else 4 * 2**20
    buf = get_range(client, start, min(size, end + tail))
    header_line = get_range(client, 0, 65536).split(b"\n", 1)[0]
    header = next(csv.reader([header_line.decode("utf-8").rstrip("\r")]))
    if index == 0:
        begin = buf.index(b"\n") + 1
    else:
        begin = BOUNDARY.search(buf).start() + 1
    if end == size:
        stop = len(buf)
    else:
        m = BOUNDARY.search(buf, end - start - 1)
        stop = m.start() + 1
    log(f"часть {index} из {PARTS}: байты [{start}, {end}) объекта {size} байт, разбираю записи [{start + begin}, {start + stop})")
    counts = Counts()
    counts.add_rows(csv.reader(io.StringIO(buf[begin:stop].decode("utf-8"), newline="")), header)
    key = f"{RUN}/parts/part-{index:02d}.json"
    client.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(counts.to_json(), ensure_ascii=False).encode())
    log(f"часть {index}: строк {counts.rows}, вакансий варианта {counts.variant}, пар уникальных {len(counts.k2)}; записано s3://{BUCKET}/{key} за {time.time() - t0:.2f} с")
    report_memory()


def run_merge():
    t0 = time.time()
    client = s3()
    keys = sorted(o["Key"] for o in client.list_objects_v2(Bucket=BUCKET, Prefix=f"{RUN}/parts/").get("Contents", []))
    log(f"собираю части: {keys}")
    counts = Counts()
    for key in keys:
        counts.merge_json(json.loads(client.get_object(Bucket=BUCKET, Key=key)["Body"].read()))
    s = counts.summary()
    log(f"строк {s['rows_in_object']}, вакансий варианта {s['variant_vacancies']}, с навыками {s['with_skills']}")
    log(f"навыков уникальных {s['distinct'][0]}, вхождений {s['total'][0]}; пар уникальных {s['distinct'][1]}, вхождений {s['total'][1]}")
    ok = compare_with_hw3(counts)
    for name, k, counter in (("k1_skills", 1, counts.k1), ("k2_pairs", 2, counts.k2)):
        out = io.StringIO()
        w = csv.writer(out)
        w.writerow([f"skill_{i}" for i in range(1, k + 1)] + ["cnt"])
        w.writerows(sorted_rows(counter))
        client.put_object(Bucket=BUCKET, Key=f"{RUN}/result/{name}.csv", Body=out.getvalue().encode())
    client.put_object(Bucket=BUCKET, Key=f"{RUN}/result/summary.json",
                      Body=json.dumps(s, ensure_ascii=False, indent=2).encode())
    log(f"результат записан в s3://{BUCKET}/{RUN}/result/ за {time.time() - t0:.2f} с")
    report_memory()
    return 0 if ok else 1


def main():
    mode = sys.argv[1]
    if mode == "local":
        run_local(sys.argv[2])
    elif mode == "upload":
        run_upload(sys.argv[2])
    elif mode == "part":
        run_part()
    elif mode == "merge":
        return run_merge()
    return 0


if __name__ == "__main__":
    sys.exit(main())
