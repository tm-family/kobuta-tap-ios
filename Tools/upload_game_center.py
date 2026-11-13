#!/usr/bin/env python3
"""Game Center のリーダーボードを App Store Connect に作り、`AppStore/game_center.json` とそろえる。

    python3 Tools/upload_game_center.py            # 反映する
    python3 Tools/upload_game_center.py --dry-run  # 読み取りの API だけ使い、何をするかを出す
    python3 Tools/upload_game_center.py --check    # App Store Connect につながず、JSON だけ検査する

やること:

- アプリの Game Center（gameCenterDetails）が無ければ作る（App Store Connect の画面で Game Center を有効にするのと同じ）
- JSON にあって App Store Connect に無いリーダーボードを作る。あるものは、違う項目だけ書き換える
- リーダーボードの言語ごとの名前と単位を、編集できるバージョン（審査に出す前）にそろえる

やらないこと:

- JSON から消したリーダーボード・言語を消す（リーダーボードの ID は消しても使い直せないので、消すのは人が画面で行う）
- 公開済みのリーダーボードの新しいバージョンを作る（名前を変えたいときは、App Store Connect の画面で行う）
- アプリのバージョンへの追加（審査に出すバージョンの「Game Center」の欄）。審査に出すときに画面で行う

リーダーボードは v2 の API（リーダーボード → バージョン → 言語）で扱う。v1 の API は 4.3 で非推奨になった。
API キーには Game Center を編集できる役割（Admin か App Manager）が要る。足りないと 403 で止まる。

認証は App Store Connect API Key（.p8）。次の環境変数でも渡せる。

    APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_PRIVATE_KEY_PATH

PyJWT が要る（--check では不要）: `python3 -m pip install pyjwt cryptography`
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

from app_store_config import ROOT, bundle_id, languages

CONFIG_PATH = ROOT / "AppStore" / "game_center.json"

FORMATTERS = {
    "INTEGER", "DECIMAL_POINT_1_PLACE", "DECIMAL_POINT_2_PLACE", "DECIMAL_POINT_3_PLACE",
    "ELAPSED_TIME_CENTISECOND", "ELAPSED_TIME_MINUTE", "ELAPSED_TIME_SECOND",
    "MONEY_POUND_DECIMAL", "MONEY_POUND", "MONEY_DOLLAR_DECIMAL", "MONEY_DOLLAR",
    "MONEY_EURO_DECIMAL", "MONEY_EURO", "MONEY_FRANC_DECIMAL", "MONEY_FRANC",
    "MONEY_KRONER_DECIMAL", "MONEY_KRONER", "MONEY_YEN",
}
SUBMISSION_TYPES = {"BEST_SCORE", "MOST_RECENT_SCORE"}
SORT_TYPES = {"ASC", "DESC"}
#: リーダーボードの項目のうち、JSON から App Store Connect に書くもの（vendorIdentifier は作るときだけ）
LEADERBOARD_FIELDS = ("referenceName", "defaultFormatter", "submissionType", "scoreSortType",
                      "scoreRangeStart", "scoreRangeEnd")
LOCALIZATION_FIELDS = ("name", "formatterSuffix", "formatterSuffixSingular")
#: 言語を書き換えられるリーダーボードのバージョンの状態（審査に出す前と、却下されたもの）
EDITABLE_VERSION_STATES = {"PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED"}
VENDOR_ID_PATTERN = re.compile(r"^[A-Za-z0-9._]{1,100}$")


def load(path: Path) -> tuple[list[dict], list[str]]:
    """JSON を読み、リーダーボードの一覧と問題点を返す。"""
    data = json.loads(path.read_text())
    leaderboards = data.get("leaderboards")
    if not isinstance(leaderboards, list) or not leaderboards:
        return [], [f"{path.name}: leaderboards が空です"]

    store_locales = {language.store_locale for language in languages()}
    problems: list[str] = []
    seen: set[str] = set()
    for index, board in enumerate(leaderboards):
        vendor_id = board.get("vendorIdentifier", "")
        where = f"leaderboards[{index}]（{vendor_id or 'ID なし'}）"
        if not VENDOR_ID_PATTERN.match(vendor_id):
            problems.append(f"{where}: vendorIdentifier は英数字・ピリオド・アンダースコアの 100 文字以内にしてください")
        if vendor_id in seen:
            problems.append(f"{where}: vendorIdentifier が重複しています")
        seen.add(vendor_id)
        if not board.get("referenceName"):
            problems.append(f"{where}: referenceName がありません")
        if board.get("defaultFormatter") not in FORMATTERS:
            problems.append(f"{where}: defaultFormatter は {', '.join(sorted(FORMATTERS))} のどれかにしてください")
        if board.get("submissionType") not in SUBMISSION_TYPES:
            problems.append(f"{where}: submissionType は {' / '.join(sorted(SUBMISSION_TYPES))} にしてください")
        if board.get("scoreSortType") not in SORT_TYPES:
            problems.append(f"{where}: scoreSortType は {' / '.join(sorted(SORT_TYPES))} にしてください")
        range_start, range_end = board.get("scoreRangeStart"), board.get("scoreRangeEnd")
        if (range_start is None) != (range_end is None):
            problems.append(f"{where}: scoreRangeStart と scoreRangeEnd は両方書くか、両方とも省いてください")
        elif range_start is not None and not (isinstance(range_start, int) and isinstance(range_end, int)
                                               and range_start < range_end):
            problems.append(f"{where}: scoreRangeStart < scoreRangeEnd の整数にしてください")

        localizations = board.get("localizations") or {}
        missing = sorted(store_locales - set(localizations))
        if missing:
            problems.append(f"{where}: languages.json の言語の名前がありません: {', '.join(missing)}")
        for locale, values in localizations.items():
            if locale not in store_locales:
                problems.append(f"{where}: {locale} は languages.json の storeLocale にありません")
            if not (values or {}).get("name"):
                problems.append(f"{where}: {locale} の name がありません")
    return leaderboards, problems


def leaderboard_attributes(board: dict) -> dict:
    return {field: board[field] for field in LEADERBOARD_FIELDS if field in board}


def localization_attributes(values: dict) -> dict:
    return {field: values[field] for field in LOCALIZATION_FIELDS if field in values}


def differences(current: dict, new: dict) -> dict:
    """new のうち current と違う項目。点数の範囲は API が文字列で返すことがあるので数として比べる。"""
    changed = {}
    for field, value in new.items():
        old = current.get(field)
        if isinstance(value, int) and old is not None:
            try:
                if int(float(old)) == value:
                    continue
            except (TypeError, ValueError):
                pass
        elif old == value:
            continue
        changed[field] = value
    return changed


def describe(changes: dict, current: dict | None = None) -> str:
    if current is None:
        return ", ".join(f"{field}={json.dumps(value, ensure_ascii=False)}" for field, value in changes.items())
    return ", ".join(
        f"{field}: {json.dumps(current.get(field), ensure_ascii=False)} → {json.dumps(value, ensure_ascii=False)}"
        for field, value in changes.items()
    )


class GameCenter:
    """Game Center のリーダーボードの読み書き（v2 の API）。"""

    def __init__(self, client, dry_run: bool):
        self.client = client
        self.dry_run = dry_run

    def ensure_detail(self, app_id: str) -> str | None:
        detail = self.client.get_or_none(f"/v1/apps/{app_id}/gameCenterDetail")
        if detail:
            return detail["id"]
        print("+ Game Center を有効にする（gameCenterDetails を作る）")
        if self.dry_run:
            return None
        created = self.client.post("/v1/gameCenterDetails", {"data": {
            "type": "gameCenterDetails",
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }})
        return created["data"]["id"]

    def leaderboards(self, detail_id: str | None) -> dict[str, dict]:
        if detail_id is None:
            return {}
        boards = self.client.get_all(f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboardsV2")
        return {board["attributes"]["vendorIdentifier"]: board for board in boards}

    def create_leaderboard(self, detail_id: str, attributes: dict) -> str:
        """リーダーボードを、最初のバージョンと一緒に作る。作ったバージョンの ID を返す。"""
        local_version_id = "${version-1}"
        created = self.client.post("/v2/gameCenterLeaderboards", {
            "data": {
                "type": "gameCenterLeaderboards",
                "attributes": attributes,
                "relationships": {
                    "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail_id}},
                    "versions": {"data": [{"type": "gameCenterLeaderboardVersions", "id": local_version_id}]},
                },
            },
            "included": [{"type": "gameCenterLeaderboardVersions", "id": local_version_id}],
        })
        board_id = created["data"]["id"]
        version = self.latest_version(board_id)
        if version is None:
            raise SystemExit(f"リーダーボード {attributes['vendorIdentifier']} のバージョンが作られていません")
        return version["id"]

    def update_leaderboard(self, board_id: str, changes: dict) -> None:
        self.client.patch(f"/v2/gameCenterLeaderboards/{board_id}", {"data": {
            "type": "gameCenterLeaderboards", "id": board_id, "attributes": changes,
        }})

    def latest_version(self, board_id: str) -> dict | None:
        versions = self.client.get_all(f"/v2/gameCenterLeaderboards/{board_id}/versions")
        return max(versions, key=lambda version: version["attributes"].get("version") or 0, default=None)

    def localizations(self, version_id: str) -> dict[str, dict]:
        entries = self.client.get_all(f"/v2/gameCenterLeaderboardVersions/{version_id}/localizations")
        return {entry["attributes"]["locale"]: entry for entry in entries}

    def create_localization(self, version_id: str, locale: str, attributes: dict) -> None:
        self.client.post("/v2/gameCenterLeaderboardLocalizations", {"data": {
            "type": "gameCenterLeaderboardLocalizations",
            "attributes": {"locale": locale, **attributes},
            "relationships": {"version": {"data": {"type": "gameCenterLeaderboardVersions", "id": version_id}}},
        }})

    def update_localization(self, localization_id: str, changes: dict) -> None:
        self.client.patch(f"/v2/gameCenterLeaderboardLocalizations/{localization_id}", {"data": {
            "type": "gameCenterLeaderboardLocalizations", "id": localization_id, "attributes": changes,
        }})


def sync_localizations(game_center: GameCenter, vendor_id: str, version: dict | None,
                       localizations: dict[str, dict]) -> int:
    """言語ごとの名前をそろえる。書き換えられないバージョンで違いがあれば、その数を返す。"""
    if version is None:
        # dry-run で、まだリーダーボードが無いとき
        for locale, values in localizations.items():
            print(f"+ {vendor_id} [{locale}] {describe(localization_attributes(values))}")
        return 0

    state = version["attributes"].get("state")
    current = game_center.localizations(version["id"])
    blocked = 0
    for locale, values in localizations.items():
        attributes = localization_attributes(values)
        entry = current.get(locale)
        changes = attributes if entry is None else differences(entry["attributes"], attributes)
        if not changes:
            continue
        if state not in EDITABLE_VERSION_STATES:
            print(f"! {vendor_id} [{locale}] バージョン {version['attributes'].get('version')} は {state} のため"
                  f"書き換えられません（App Store Connect の画面で新しいバージョンを作ってください）: "
                  f"{describe(changes, None if entry is None else entry['attributes'])}")
            blocked += 1
            continue
        if entry is None:
            print(f"+ {vendor_id} [{locale}] {describe(changes)}")
            if not game_center.dry_run:
                game_center.create_localization(version["id"], locale, changes)
        else:
            print(f"~ {vendor_id} [{locale}] {describe(changes, entry['attributes'])}")
            if not game_center.dry_run:
                game_center.update_localization(entry["id"], changes)
    return blocked


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=CONFIG_PATH, help="リーダーボードの定義（JSON）")
    parser.add_argument("--bundle-id", help="省略すると Configs/Project.xcconfig から読む")
    parser.add_argument("--key-id", default=os.environ.get("APP_STORE_CONNECT_KEY_ID"))
    parser.add_argument("--issuer-id", default=os.environ.get("APP_STORE_CONNECT_ISSUER_ID"))
    parser.add_argument(
        "--private-key",
        type=Path,
        default=os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH"),
        help="App Store Connect API Key の .p8",
    )
    parser.add_argument("--check", action="store_true", help="App Store Connect につながず、JSON だけ検査する")
    parser.add_argument("--dry-run", action="store_true", help="何も書き換えず、何をするかだけ出す")
    args = parser.parse_args()

    leaderboards, problems = load(args.config)
    if problems:
        raise SystemExit("\n".join(problems))
    if args.check:
        for board in leaderboards:
            names = " / ".join(f"{locale}: {values['name']}" for locale, values in board["localizations"].items())
            print(f"  {board['vendorIdentifier']}（{board['submissionType']}・{board['scoreSortType']}）{names}")
        print(f"問題なし: リーダーボード {len(leaderboards)} 件")
        return 0

    missing_key = [
        name for name, value in
        [("--key-id", args.key_id), ("--issuer-id", args.issuer_id), ("--private-key", args.private_key)]
        if not value
    ]
    if missing_key:
        raise SystemExit(f"認証情報が足りません: {', '.join(missing_key)}")

    from app_store_connect import ApiError, AppStoreConnect

    client = AppStoreConnect(
        args.key_id, args.issuer_id, Path(args.private_key).read_text(), dry_run=args.dry_run
    )
    game_center = GameCenter(client, args.dry_run)

    try:
        app = client.find_app(args.bundle_id or bundle_id())
        print(f"対象: {app['attributes']['name']}（{app['attributes']['bundleId']}）")
        detail_id = game_center.ensure_detail(app["id"])
        existing = game_center.leaderboards(detail_id)

        blocked = 0
        for board in leaderboards:
            vendor_id = board["vendorIdentifier"]
            attributes = leaderboard_attributes(board)
            current = existing.get(vendor_id)
            if current is None:
                print(f"+ リーダーボード {vendor_id} を作る: {describe(attributes)}")
                version = None
                if not args.dry_run:
                    version_id = game_center.create_leaderboard(detail_id, {"vendorIdentifier": vendor_id, **attributes})
                    version = {"id": version_id, "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}
            else:
                changes = differences(current["attributes"], attributes)
                if changes:
                    print(f"~ リーダーボード {vendor_id}: {describe(changes, current['attributes'])}")
                    if not args.dry_run:
                        game_center.update_leaderboard(current["id"], changes)
                version = game_center.latest_version(current["id"])
            blocked += sync_localizations(game_center, vendor_id, version, board["localizations"])
    except ApiError as error:
        if error.status == 403:
            raise SystemExit(
                "App Store Connect API Key の権限が足りません（Game Center の編集には Admin か App Manager の役割が要ります）。\n"
                f"{error}"
            ) from None
        raise

    if blocked:
        print(f"書き換えられなかった言語が {blocked} 件あります")
        return 1
    print("完了（dry-run）" if args.dry_run else "完了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
