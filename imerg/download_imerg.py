"""GPM IMERG Final 30분 자료(V07)를 장마 관측창만 잘라서 받는다.

NASA 클라우드 OPeNDAP 서버에서 강수량(precipitation)만, 북위 28~40°·동경 119~132° 영역만 받는다.
전 지구 파일(2.8 MB) 대신 파일당 수십 KB라서 한 시즌(6~9월, 약 5,900개)이 약 200 MB다.

사용법 (이 파일이 있는 폴더에서):
    python download_imerg.py 2023-07-15 2023-07-15     # 먼저 하루(48개)만 시험
    python download_imerg.py 2023-06-01 2023-09-30     # 한 시즌

처음 실행하면 Earthdata 아이디와 비밀번호를 터미널에서 묻는다. 비밀번호는 화면에 보이지 않는다.
받은 파일은 raw 폴더에 쌓이고, 이미 받은 파일은 건너뛰므로 중간에 끊겨도 다시 실행하면 이어서 받는다.
"""
import os
import sys
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

import earthaccess

COLLECTION = "C2723754847-GES_DISC"           # GPM_3IMERGHH V07
# 격자 번호: 경도 -179.95~179.95(3600칸), 위도 -89.95~89.95(1800칸), 0.1° 간격
LON0, LON1 = 2990, 3119                         # 동경 119.05~131.95° (서해~동해)
LAT0, LAT1 = 1180, 1299                         # 북위 28.05~39.95°
CONSTRAINT = (f"/Grid/precipitation[0][{LON0}:1:{LON1}][{LAT0}:1:{LAT1}];"
              f"/Grid/lon[{LON0}:1:{LON1}];/Grid/lat[{LAT0}:1:{LAT1}];/Grid/time")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
WORKERS = 6


def subset_url(granule_ur):
    return ("https://opendap.earthdata.nasa.gov/collections/" + COLLECTION + "/granules/"
            + urllib.parse.quote(granule_ur) + ".dap.nc4?dap4.ce="
            + urllib.parse.quote(CONSTRAINT, safe=""))


def fetch(session, granule_ur):
    name = granule_ur.split(":")[-1].replace(".HDF5", ".nc4")
    path = os.path.join(OUT_DIR, name)
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return "skip"
    url = subset_url(granule_ur)
    last = ""
    for attempt in range(4):
        try:
            r = session.get(url, timeout=(30, 180))
            if r.status_code in (401, 403):
                return ("auth", name, r.status_code, r.url[:120], " ".join(r.text[:300].split()))
            ctype = r.headers.get("Content-Type", "")
            if r.status_code == 200 and "html" not in ctype.lower() and len(r.content) > 1000:
                with open(path + ".part", "wb") as f:
                    f.write(r.content)
                os.replace(path + ".part", path)
                return "ok"
            last = f"HTTP {r.status_code}, {ctype}, {len(r.content)} B: " + " ".join(r.text[:200].split())
        except Exception as e:
            last = f"{type(e).__name__}: {e}"[:300]
        print(f"    [{name[21:43]}] 재시도 {attempt + 1}/4 - {last}", flush=True)
        time.sleep(3 * (attempt + 1))
    return ("fail", name, last)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    start, end = sys.argv[1], sys.argv[2]
    os.makedirs(OUT_DIR, exist_ok=True)

    earthaccess.login()   # 환경변수·.netrc가 없으면 터미널에서 아이디·비밀번호를 묻는다
    results = earthaccess.search_data(short_name="GPM_3IMERGHH", version="07",
                                      temporal=(start, end + "T23:59:59"))
    urs = sorted(g["umm"]["GranuleUR"] for g in results)
    print(f"{start} ~ {end}: 파일 {len(urs)}개를 받습니다 (예상 {len(urs) * 40 / 1024:.0f} MB 안팎)", flush=True)

    session = earthaccess.get_requests_https_session()

    # 본격적으로 받기 전에 파일 하나로 서버 응답을 확인한다
    t0 = time.time()
    print("첫 파일로 서버 응답 확인 중... (최대 3분)", flush=True)
    try:
        r = session.get(subset_url(urs[0]), timeout=(30, 180))
        print(f"  응답 HTTP {r.status_code}, {r.headers.get('Content-Type', '')}, "
              f"{len(r.content)} B, {time.time() - t0:.1f}초", flush=True)
        if r.status_code != 200:
            print("  서버 메시지:", " ".join(r.text[:400].split()), flush=True)
    except Exception as e:
        print(f"  요청 실패 ({time.time() - t0:.1f}초): {type(e).__name__}: {e}", flush=True)
    done = skip = 0
    problems = []
    with ThreadPoolExecutor(WORKERS) as pool:
        futures = [pool.submit(fetch, session, ur) for ur in urs]
        for i, fut in enumerate(as_completed(futures), 1):
            res = fut.result()
            if res == "ok":
                done += 1
            elif res == "skip":
                skip += 1
            else:
                problems.append(res)
                if res[0] == "auth":
                    print("\n권한 오류(401/403): Earthdata 웹사이트 > 프로필 > Applications > Authorized Apps에서"
                          "\n'NASA GESDISC DATA ARCHIVE'를 승인한 뒤 다시 실행하세요.")
                    pool.shutdown(wait=False, cancel_futures=True)
                    break
            if i % 10 == 0 or i == len(urs):
                print(f"  {i}/{len(urs)}  새로 받음 {done}, 건너뜀 {skip}, 실패 {len(problems)}", flush=True)

    print(f"\n완료: 새로 받음 {done}, 이미 있음 {skip}, 실패 {len(problems)}  →  {OUT_DIR}")
    if problems:
        print("실패한 파일은 다시 실행하면 이어서 받습니다:", problems[:5], "..." if len(problems) > 5 else "")


if __name__ == "__main__":
    main()
