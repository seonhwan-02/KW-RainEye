"""GPM IMERG 30분 자료(V07, Final 또는 Early)를 Harmony로 잘라서 받는다 (Earthdata Search 웹 주문과 같은 서버).

영역 북위 28~40°·동경 119~132°, 변수 precipitation 하나, netCDF-4.
덜 받은 달을 한 달 단위로 한꺼번에 주문하고(서버가 동시에 처리), 끝난 순서대로 내려받는다.
다 받은 달은 건너뛰고 전에 넣은 주문은 다시 쓰므로, 중간에 끊겨도 다시 실행하면 이어서 받는다.
2023과 2024를 창 두 개에서 동시에 돌려도 된다.

사용법 (이 파일이 있는 폴더에서):
    python harmony_download.py 2023-07-15 2023-07-15     # 먼저 하루(48개)만 시험
    python harmony_download.py 2023-06-01 2023-09-30     # 한 시즌 (Final, 사후 자료)
    python harmony_download.py 2023-06-01 2023-09-30 early   # 한 시즌 (Early, 실시간판)

아이디와 비밀번호는 터미널에서 묻는다. 비밀번호는 화면에 보이지 않고 어디에도 저장하지 않는다.
받은 파일은 바탕화면 K-RainEye_IMERG 폴더에 달별(202307 등)로 쌓인다. Early는 그 안의 early 폴더(early/202307 등)에 따로 쌓인다.
Final은 앞뒤 시간의 위성 자료로 보간한 사후 자료, Early는 과거 자료만 쓴 실시간판이라 '큐' 모의에는 Early가 현실적이다.
"""
import getpass
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

from harmony import BBox, Client, Collection, Request

COLLECTIONS = {"final": "C2723754847-GES_DISC",   # GPM_3IMERGHH  V07 (Final, 사후 자료)
               "early": "C2723758340-GES_DISC"}   # GPM_3IMERGHHE V07 (Early, 실시간판)
BOX = BBox(119, 28, 132, 40)                     # 서, 남, 동, 북 [도]
OUT_ROOT = os.path.join(os.path.expanduser("~"), "Desktop", "K-RainEye_IMERG")
JOBS_FILE = os.path.join(OUT_ROOT, "jobs.json")  # 달별 주문 번호 (다시 실행할 때 재주문하지 않으려고)
WORKERS = 4
VAR_CANDIDATES = (["Grid/precipitation"], ["precipitation"])


def month_chunks(start, end):
    """[start, end] 구간을 달 단위로 자른다."""
    s = start
    while s <= end:
        nxt = (s.replace(day=1) + timedelta(days=32)).replace(day=1)
        e = min(end, nxt - timedelta(seconds=1))
        yield s, e
        s = nxt


def submit(client, s, e, collection):
    last = None
    for var in VAR_CANDIDATES:
        req = Request(collection=Collection(id=collection), spatial=BOX,
                      temporal={"start": s, "stop": e}, variables=var,
                      format="application/x-netcdf4", skip_preview=True)
        try:
            return client.submit(req)
        except Exception as ex:          # 변수 이름이 안 맞으면 다음 후보로
            last = ex
            print(f"  변수 {var[0]} 로 주문 실패: {ex}", flush=True)
    raise last


def main():
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] not in COLLECTIONS):
        print(__doc__)
        sys.exit(1)
    product = sys.argv[3] if len(sys.argv) == 4 else "final"
    collection = COLLECTIONS[product]
    root = OUT_ROOT if product == "final" else os.path.join(OUT_ROOT, product)
    print(f"자료: IMERG {product} ({collection}) -> {root}", flush=True)
    start = datetime.fromisoformat(sys.argv[1])
    end = datetime.fromisoformat(sys.argv[2]) + timedelta(hours=23, minutes=59, seconds=59)

    user = input("Earthdata 아이디: ").strip()
    pw = getpass.getpass("Earthdata 비밀번호 (입력해도 화면에 안 보임): ")
    try:
        client = Client(auth=(user, pw))
    except Exception as ex:
        print("로그인 실패 - 아이디·비밀번호를 확인하세요:", ex)
        sys.exit(1)

    # 1단계: 아직 덜 받은 달은 전부 한꺼번에 주문한다 (NASA 서버가 여러 달을 동시에 자른다)
    jobs = load_jobs()
    todo, total = [], 0
    for s, e in month_chunks(start, end):
        out = os.path.join(root, s.strftime("%Y%m"))
        os.makedirs(out, exist_ok=True)
        expected = round(((e - s).total_seconds() + 1) / 1800)
        have = keys_in(out)
        tag = f"{s:%Y-%m-%d} ~ {e:%Y-%m-%d}"
        if len(have) >= expected:
            print(f"{tag}: 이미 {len(have)}개 있음, 건너뜀")
            total += len(have)
            continue
        # 전에 넣은 주문이 서버에 남아 있으면 다시 주문하지 않고 그 결과를 이어서 받는다
        jkey = f"{s:%Y%m%d}-{e:%Y%m%d}" if product == "final" else f"{product}:{s:%Y%m%d}-{e:%Y%m%d}"
        job = jobs.get(jkey)
        if job:
            try:
                st = client.status(job).get("status")
            except Exception:
                st = None
            if st in ("failed", "canceled", None):
                job = None
            elif st == "paused":
                client.resume(job)
        if not job:
            print(f"{tag}: 파일 {expected}개 주문", flush=True)
            job = submit(client, s, e, collection)
            if isinstance(job, dict):            # 아주 작은 요청은 바로 끝나서 결과가 곧장 온다
                job = job.get("jobID")
            jobs[jkey] = job
            save_jobs({jkey: job})
        else:
            print(f"{tag}: 전에 넣은 주문 {job}을 이어서 씀", flush=True)
        todo.append((tag, out, expected, jkey, job))

    # 2단계: 주문한 달을 차례로 기다렸다가 내려받는다 (앞 달을 기다리는 동안 뒤 달도 서버에서 처리되고 있다)
    missing = 0
    for i, (tag, out, expected, jkey, job) in enumerate(todo, 1):
        print(f"\n[{i}/{len(todo)}] {tag}: 주문 {job} - NASA 서버 처리 기다리는 중", flush=True)
        client.wait_for_processing(job, show_progress=True)
        have = keys_in(out)
        urls = [u for u in client.result_urls(job) if key_of(u) and key_of(u) not in have]
        print(f"  내려받는 중: 새로 {len(urls)}개 (이미 {len(have)}개 있음)", flush=True)
        ok, failed = download(client, urls, out)
        n_now = len(keys_in(out))
        print(f"  {tag}: 새로 {ok}개, 실패 {len(failed)}개 -> 이 달 {n_now}/{expected}개", flush=True)
        if n_now < expected and client.status(job).get("status") == "complete_with_errors":
            drop_job(jkey)                   # 서버 쪽에서 일부가 실패한 주문이면 다음 실행 때 새로 주문
        if failed:
            print("  실패한 파일은 같은 명령을 다시 실행하면 이어서 받습니다. 예:", failed[0][:120], flush=True)
        total += n_now
        missing += max(0, expected - n_now)

    print(f"\n전체: 파일 {total}개 -> {root}" + (f", 아직 {missing}개 남음 (다시 실행하세요)" if missing else ", 모두 완료"))


def key_of(name):
    m = re.search(r"\d{8}-S\d{6}", name)
    return m.group(0) if m else None


def keys_in(folder):
    """폴더에 있는 파일의 시각(날짜+시작시각) 집합. 주문마다 붙는 번호가 달라도 같은 시각은 하나로 센다."""
    return {k for f in os.listdir(folder) if f.endswith(".nc4") and (k := key_of(f))}


def load_jobs():
    try:
        with open(JOBS_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_jobs(update):
    """주문 번호를 파일에 더한다. 다른 창에서 동시에 돌려도 서로 덮어쓰지 않도록 읽어서 합친 뒤 쓴다."""
    os.makedirs(OUT_ROOT, exist_ok=True)
    jobs = load_jobs()
    jobs.update(update)
    with open(JOBS_FILE, "w", encoding="utf-8") as f:
        json.dump(jobs, f, indent=1)


def drop_job(jkey):
    jobs = load_jobs()
    jobs.pop(jkey, None)
    with open(JOBS_FILE, "w", encoding="utf-8") as f:
        json.dump(jobs, f, indent=1)


def download(client, urls, out):
    """파일마다 최대 5번 재시도한다. 하나가 실패해도 나머지는 계속 받는다."""
    def one(u):
        last = None
        for attempt in range(5):
            try:
                client._download_file(u, directory=out, overwrite=True)
                return None
            except Exception as ex:
                last = ex
                time.sleep(5 * (attempt + 1))
        return f"{key_of(u)}: {type(last).__name__} {str(last)[:80]}"

    ok, failed = 0, []
    with ThreadPoolExecutor(WORKERS) as pool:
        for i, res in enumerate(pool.map(one, urls), 1):
            if res is None:
                ok += 1
            else:
                failed.append(res)
            if i % 100 == 0 or i == len(urls):
                print(f"    {i}/{len(urls)}  받음 {ok}, 실패 {len(failed)}", flush=True)
    return ok, failed


if __name__ == "__main__":
    main()
