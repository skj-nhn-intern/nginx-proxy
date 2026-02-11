#!/usr/bin/env python3
"""
중지된 NHN Cloud 인스턴스로부터 nginx-proxy 이미지를 생성하고 active 될 때까지 대기.
환경 변수: TOKEN, COMPUTE_URL, INSTANCE_ID, GIT_SHA(선택), VOLUME_URL(선택)
GITHUB_OUTPUT에 image_id, image_name 기록.
"""
import os
import sys
import time
from datetime import datetime

import requests


def _image_base_url(compute_url: str) -> str:
    base = compute_url.split("/v2/")[0]
    return base.replace("-instance-", "-image-")


def _volume_url_from_compute(compute_url: str) -> str:
    parts = compute_url.split("/v2/", 1)
    base = parts[0]
    tenant_id = (parts[1] or "").strip("/") if len(parts) > 1 else ""
    replaced = base.replace("-instance-", "-block-storage-")
    if replaced == base:
        replaced = base.replace("-instance-", "-volume-")
    if replaced != base and tenant_id:
        return f"{replaced}/v2/{tenant_id}"
    return replaced if replaced != base else ""


def main() -> None:
    token = os.environ["TOKEN"]
    compute_url = os.environ["COMPUTE_URL"]
    server_id = os.environ["INSTANCE_ID"]
    git_sha = os.environ.get("GIT_SHA", "")
    volume_url = os.environ.get("VOLUME_URL", "").strip()
    if not volume_url:
        volume_url = _volume_url_from_compute(compute_url)
    headers = {
        "X-Auth-Token": token,
        "Content-Type": "application/json",
    }

    image_name = f"nginx-proxy-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    image_base = _image_base_url(compute_url)

    create_image_payload = {
        "createImage": {
            "name": image_name,
            "visibility": "shared",
            "metadata": {
                "purpose": "github-actions-build",
                "app": "nginx-proxy",
                "git_sha": git_sha,
            },
        }
    }
    r = requests.post(
        f"{compute_url}/servers/{server_id}/action",
        headers=headers,
        json=create_image_payload,
    )

    image_id = None
    if r.ok:
        try:
            body = r.json()
            image_id = (body.get("image_id") or body.get("imageId") or "").strip()
        except Exception:
            pass
    else:
        msg = (r.text or "").lower()
        if "block storage volume" in msg and volume_url:
            print("ℹ️  인스턴스가 block storage volume 루트라 createImage 불가. 볼륨 업로드로 이미지 생성 시도...")
            att = requests.get(
                f"{compute_url}/servers/{server_id}/os-volume_attachments",
                headers=headers,
            )
            att.raise_for_status()
            attachments = att.json().get("volumeAttachments") or att.json().get("volume_attachments") or []
            if not attachments:
                print("❌ 서버에 연결된 볼륨을 찾을 수 없습니다.", file=sys.stderr)
                sys.exit(1)
            vol_id = attachments[0].get("volumeId") or attachments[0].get("id")
            upload_body = {
                "os-volume_upload_image": {
                    "image_name": image_name,
                    "container_format": "bare",
                    "disk_format": "raw",
                    "visibility": "shared",
                    "force": True,
                }
            }
            up = requests.post(
                f"{volume_url}/volumes/{vol_id}/action",
                headers=headers,
                json=upload_body,
            )
            if not up.ok:
                print(f"❌ 볼륨 업로드 API 응답: {up.status_code}", file=sys.stderr)
                sys.exit(1)
            try:
                up_data = up.json()
                image_id = (
                    up_data.get("os-volume_upload_image", {}).get("image_id") or
                    up_data.get("image_id") or
                    up_data.get("imageId") or
                    (up_data.get("os-volume_upload_image") or {}).get("imageId") or
                    ""
                ).strip()
            except Exception:
                image_id = None
        elif "block storage volume" in msg:
            print("❌ 이미지 생성 불가: 인스턴스가 block storage volume 루트입니다.", file=sys.stderr)
            sys.exit(1)
        else:
            print(f"❌ 이미지 생성 API 응답: {r.status_code}", file=sys.stderr)
            r.raise_for_status()

    max_wait = 900
    start = time.time()
    while time.time() - start < max_wait:
        if image_id:
            r = requests.get(f"{image_base}/v2/images/{image_id}", headers=headers)
            if r.status_code == 404:
                time.sleep(15)
                continue
            r.raise_for_status()
            image = r.json().get("image") or r.json()
            status = image.get("status", "")
        else:
            r = requests.get(
                f"{image_base}/v2/images?name={image_name}",
                headers=headers,
            )
            r.raise_for_status()
            images = r.json().get("images", [])
            if not images:
                time.sleep(15)
                continue
            images.sort(key=lambda img: img.get("created_at") or "", reverse=True)
            image = images[0]
            image_id = image["id"]
            status = image.get("status", "")
        if status == "active":
            print(f"✅ 이미지 생성 완료: {image_id}")
            out = os.environ.get("GITHUB_OUTPUT")
            if out:
                with open(out, "a") as f:
                    f.write(f"image_id={image_id}\n")
                    f.write(f"image_name={image_name}\n")
            return
        print(f"  상태: {status}, 대기 중...")
        time.sleep(15)

    print("❌ 타임아웃: 이미지가 생성되지 않았습니다", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
