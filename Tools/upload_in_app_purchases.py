#!/usr/bin/env python3
"""アプリ内課金を App Store Connect に作り、`AppStore/in_app_purchases.json` とそろえる。

    python3 Tools/upload_in_app_purchases.py            # 反映する
    python3 Tools/upload_in_app_purchases.py --dry-run  # 読み取りの API だけ使い、何をするかを出す
    python3 Tools/upload_in_app_purchases.py --check    # App Store Connect につながず、JSON だけ検査する

やること:

- JSON にあって App Store Connect に無い課金を作る。あるものは、違う項目（参照名・ファミリー共有）だけ書き換える
- 言語ごとの表示名と説明を作る・書き換える
- 価格を、基準の国の値段（価格帯）にそろえる。ほかの国は Apple が自動で換算する
- 配信地域を、excludedTerritories を除くすべての国にそろえる（新しく増えた国でも売る）

やらないこと:

- JSON から消した課金・言語を消す（商品 ID は消しても使い直せないので、消すのは人が画面で行う）
- ファミリー共有を true から false に戻す（App Store Connect でも戻せない）
- 審査用のスクリーンショットと審査メモ、審査への提出（最初の課金は、アプリのバージョンと一緒に審査に出す）

課金は v2 の API（`/v2/inAppPurchases`）で扱う。
API キーには課金を編集できる役割（Admin か App Manager）が要る。足りないと 403 で止まる。
課金を作る前に、App Store Connect の「ビジネス」で「有料 App」の契約が有効になっている必要がある。

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

CONFIG_PATH = ROOT / "AppStore" / "in_app_purchases.json"

TYPES = {"NON_CONSUMABLE", "CONSUMABLE", "NON_RENEWING_SUBSCRIPTION"}
PRODUCT_ID_PATTERN = re.compile(r"^[A-Za-z0-9._]{1,100}$")
TERRITORY_PATTERN = re.compile(r"^[A-Z]{3}$")
REFERENCE_NAME_LIMIT = 64
#: 言語ごとの表示名と説明の文字数の上限（App Store Connect の上限）
NAME_LIMIT = 30
DESCRIPTION_LIMIT = 45


def load(path: Path) -> tuple[list[dict], list[str]]:
    """JSON を読み、課金の一覧と問題点を返す。"""
    data = json.loads(path.read_text())
    purchases = data.get("inAppPurchases")
    if not isinstance(purchases, list) or not purchases:
        return [], [f"{path.name}: inAppPurchases が空です"]

    store_locales = {language.store_locale for language in languages()}
    problems: list[str] = []
    seen: set[str] = set()
    for index, purchase in enumerate(purchases):
        product_id = purchase.get("productId", "")
        where = f"inAppPurchases[{index}]（{product_id or 'ID なし'}）"
        if not PRODUCT_ID_PATTERN.match(product_id):
            problems.append(f"{where}: productId は英数字・ピリオド・アンダースコアの 100 文字以内にしてください")
        if product_id in seen:
            problems.append(f"{where}: productId が重複しています")
        seen.add(product_id)
        reference_name = purchase.get("referenceName", "")
        if not reference_name or len(reference_name) > REFERENCE_NAME_LIMIT:
            problems.append(f"{where}: referenceName は 1〜{REFERENCE_NAME_LIMIT} 文字にしてください")
        if purchase.get("type") not in TYPES:
            problems.append(f"{where}: type は {' / '.join(sorted(TYPES))} のどれかにしてください")
        if not isinstance(purchase.get("familySharable"), bool):
            problems.append(f"{where}: familySharable は true か false にしてください")

        price = purchase.get("price") or {}
        if not TERRITORY_PATTERN.match(price.get("baseTerritory", "")):
            problems.append(f"{where}: price.baseTerritory は国の ID（JPN など）にしてください")
        if not isinstance(price.get("customerPrice"), (int, float)) or price.get("customerPrice", 0) <= 0:
            problems.append(f"{where}: price.customerPrice は 0 より大きい数にしてください")
        excluded = purchase.get("excludedTerritories", [])
        if not isinstance(excluded, list) or not all(TERRITORY_PATTERN.match(str(item)) for item in excluded):
            problems.append(f"{where}: excludedTerritories は国の ID（CHN など）の配列にしてください")
        elif price.get("baseTerritory") in excluded:
            problems.append(f"{where}: 基準の国（{price.get('baseTerritory')}）を excludedTerritories に入れないでください")

        localizations = purchase.get("localizations") or {}
        missing = sorted(store_locales - set(localizations))
        if missing:
            problems.append(f"{where}: languages.json の言語の表示名がありません: {', '.join(missing)}")
        for locale, values in localizations.items():
            values = values or {}
            if locale not in store_locales:
                problems.append(f"{where}: {locale} は languages.json の storeLocale にありません")
            name, description = values.get("name", ""), values.get("description", "")
            if not name or len(name) > NAME_LIMIT:
                problems.append(f"{where}: {locale} の name は 1〜{NAME_LIMIT} 文字にしてください（{len(name)} 文字）")
            if not description or len(description) > DESCRIPTION_LIMIT:
                problems.append(
                    f"{where}: {locale} の description は 1〜{DESCRIPTION_LIMIT} 文字にしてください（{len(description)} 文字）"
                )
    return purchases, problems


def describe(changes: dict, current: dict | None = None) -> str:
    if current is None:
        return ", ".join(f"{field}={json.dumps(value, ensure_ascii=False)}" for field, value in changes.items())
    return ", ".join(
        f"{field}: {json.dumps(current.get(field), ensure_ascii=False)} → {json.dumps(value, ensure_ascii=False)}"
        for field, value in changes.items()
    )


def same_price(value, expected: float) -> bool:
    """API は値段を文字列（"100" や "0.99"）で返すので、数として比べる。"""
    try:
        return abs(float(value) - float(expected)) < 0.0001
    except (TypeError, ValueError):
        return False


class InAppPurchases:
    """アプリ内課金の読み書き（v2 の API）。"""

    def __init__(self, client, dry_run: bool):
        self.client = client
        self.dry_run = dry_run

    def existing(self, app_id: str) -> dict[str, dict]:
        purchases = self.client.get_all(f"/v1/apps/{app_id}/inAppPurchasesV2")
        return {purchase["attributes"]["productId"]: purchase for purchase in purchases}

    def create(self, app_id: str, purchase: dict) -> str:
        created = self.client.post("/v2/inAppPurchases", {"data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": purchase["referenceName"],
                "productId": purchase["productId"],
                "inAppPurchaseType": purchase["type"],
                "familySharable": purchase["familySharable"],
            },
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }})
        return created["data"]["id"]

    def update(self, purchase_id: str, changes: dict) -> None:
        self.client.patch(f"/v2/inAppPurchases/{purchase_id}", {"data": {
            "type": "inAppPurchases", "id": purchase_id, "attributes": changes,
        }})

    # MARK: 言語

    def localizations(self, purchase_id: str) -> dict[str, dict]:
        entries = self.client.get_all(f"/v2/inAppPurchases/{purchase_id}/inAppPurchaseLocalizations")
        return {entry["attributes"]["locale"]: entry for entry in entries}

    def create_localization(self, purchase_id: str, locale: str, attributes: dict) -> None:
        self.client.post("/v1/inAppPurchaseLocalizations", {"data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": locale, **attributes},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": purchase_id}}},
        }})

    def update_localization(self, localization_id: str, changes: dict) -> None:
        self.client.patch(f"/v1/inAppPurchaseLocalizations/{localization_id}", {"data": {
            "type": "inAppPurchaseLocalizations", "id": localization_id, "attributes": changes,
        }})

    # MARK: 価格

    def price_point(self, purchase_id: str, territory: str, customer_price: float) -> dict:
        """基準の国の価格帯から、値段が一致するものを探す。無ければ、近い値段を出して止まる。"""
        points = self.client.get_all(
            f"/v2/inAppPurchases/{purchase_id}/pricePoints", {"filter[territory]": territory}
        )
        for point in points:
            if same_price(point["attributes"].get("customerPrice"), customer_price):
                return point
        prices = sorted(float(point["attributes"]["customerPrice"]) for point in points
                        if point["attributes"].get("customerPrice") is not None)
        nearby = [price for price in prices if abs(price - customer_price) <= max(customer_price, 1)][:10]
        raise SystemExit(
            f"{territory} の価格帯に {customer_price:g} がありません。近い値段: {', '.join(f'{p:g}' for p in nearby)}"
        )

    def current_base_price(self, purchase_id: str, territory: str) -> float | None:
        """いまの価格（基準の国の値段）。まだ価格を設定していなければ None。"""
        schedule = self.client.get_or_none(f"/v2/inAppPurchases/{purchase_id}/iapPriceSchedule")
        if schedule is None:
            return None
        response = self.client.get(
            f"/v1/inAppPurchasePriceSchedules/{schedule['id']}/manualPrices",
            {"include": "inAppPurchasePricePoint,territory", "filter[territory]": territory, "limit": 50},
        )
        points = {
            item["id"]: item for item in response.get("included", [])
            if item["type"] == "inAppPurchasePricePoints"
        }
        for price in response.get("data", []):
            # 予定の値上げ・値下げ（startDate が未来）ではなく、いまの値段を採る
            if price["attributes"].get("startDate"):
                continue
            point_ref = price.get("relationships", {}).get("inAppPurchasePricePoint", {}).get("data") or {}
            point = points.get(point_ref.get("id"))
            if point is not None:
                return float(point["attributes"]["customerPrice"])
        return None

    def set_price(self, purchase_id: str, territory: str, price_point_id: str) -> None:
        """価格を設定する（価格のスケジュールを作り直す）。ほかの国は Apple が自動で換算する。"""
        local_price_id = "${price-1}"
        self.client.post("/v1/inAppPurchasePriceSchedules", {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": purchase_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": territory}},
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": local_price_id}]},
                },
            },
            "included": [{
                "type": "inAppPurchasePrices",
                "id": local_price_id,
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": purchase_id}},
                    "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": price_point_id}},
                },
            }],
        })

    # MARK: 配信地域

    def all_territories(self) -> set[str]:
        return {territory["id"] for territory in self.client.get_all("/v1/territories")}

    def available_territories(self, purchase_id: str) -> set[str] | None:
        """いま売っている国。まだ配信地域を設定していなければ None。"""
        availability = self.client.get_or_none(f"/v2/inAppPurchases/{purchase_id}/inAppPurchaseAvailability")
        if availability is None:
            return None
        territories = self.client.get_all(
            f"/v1/inAppPurchaseAvailabilities/{availability['id']}/availableTerritories"
        )
        return {territory["id"] for territory in territories}

    def set_territories(self, purchase_id: str, territories: set[str]) -> None:
        self.client.post("/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": purchase_id}},
                "availableTerritories": {"data": [
                    {"type": "territories", "id": territory} for territory in sorted(territories)
                ]},
            },
        }})


def sync_purchase(store: InAppPurchases, app_id: str, purchase: dict, current: dict | None,
                  all_territories: set[str]) -> None:
    product_id = purchase["productId"]

    # 商品
    if current is None:
        print(f"+ 課金 {product_id} を作る: type={purchase['type']}, name={purchase['referenceName']!r}, "
              f"familySharable={purchase['familySharable']}")
        purchase_id = None if store.dry_run else store.create(app_id, purchase)
    else:
        purchase_id = current["id"]
        attributes = current["attributes"]
        if attributes.get("inAppPurchaseType") != purchase["type"]:
            raise SystemExit(f"{product_id}: 種類は作ったあとに変えられません"
                             f"（App Store Connect は {attributes.get('inAppPurchaseType')}、JSON は {purchase['type']}）")
        changes = {}
        if attributes.get("name") != purchase["referenceName"]:
            changes["name"] = purchase["referenceName"]
        if purchase["familySharable"] and not attributes.get("familySharable"):
            changes["familySharable"] = True
        elif not purchase["familySharable"] and attributes.get("familySharable"):
            print(f"! {product_id}: ファミリー共有は一度オンにするとオフに戻せません（App Store Connect はオンのまま）")
        if changes:
            print(f"~ 課金 {product_id}: {describe(changes, attributes)}")
            if not store.dry_run:
                store.update(purchase_id, changes)
        print(f"  {product_id} の状態: {attributes.get('state')}")

    # 言語ごとの表示名と説明
    existing = {} if purchase_id is None else store.localizations(purchase_id)
    for locale, values in purchase["localizations"].items():
        attributes = {"name": values["name"], "description": values["description"]}
        entry = existing.get(locale)
        if entry is None:
            print(f"+ {product_id} [{locale}] {describe(attributes)}")
            if not store.dry_run:
                store.create_localization(purchase_id, locale, attributes)
            continue
        changes = {field: value for field, value in attributes.items() if entry["attributes"].get(field) != value}
        if changes:
            print(f"~ {product_id} [{locale}] {describe(changes, entry['attributes'])}")
            if not store.dry_run:
                store.update_localization(entry["id"], changes)

    # 価格
    territory, customer_price = purchase["price"]["baseTerritory"], purchase["price"]["customerPrice"]
    if purchase_id is None:
        print(f"+ {product_id} の価格を {territory} で {customer_price:g} にする（課金を作ったあとに価格帯を探す）")
    else:
        current_price = store.current_base_price(purchase_id, territory)
        if current_price is None or not same_price(current_price, customer_price):
            point = store.price_point(purchase_id, territory, customer_price)
            before = "未設定" if current_price is None else f"{current_price:g}"
            print(f"~ {product_id} の価格（{territory}）: {before} → {customer_price:g}")
            if not store.dry_run:
                store.set_price(purchase_id, territory, point["id"])

    # 配信地域
    excluded = set(purchase.get("excludedTerritories", []))
    unknown = excluded - all_territories
    if unknown:
        raise SystemExit(f"{product_id}: excludedTerritories に App Store Connect に無い国があります: {', '.join(sorted(unknown))}")
    wanted = all_territories - excluded
    available = None if purchase_id is None else store.available_territories(purchase_id)
    if available != wanted:
        before = "未設定" if available is None else f"{len(available)} か国"
        print(f"~ {product_id} の配信地域: {before} → {len(wanted)} か国（除く: {', '.join(sorted(excluded)) or 'なし'}）")
        if not store.dry_run and purchase_id is not None:
            store.set_territories(purchase_id, wanted)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=CONFIG_PATH, help="課金の定義（JSON）")
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

    purchases, problems = load(args.config)
    if problems:
        raise SystemExit("\n".join(problems))
    if args.check:
        for purchase in purchases:
            names = " / ".join(f"{locale}: {values['name']}" for locale, values in purchase["localizations"].items())
            price = purchase["price"]
            print(f"  {purchase['productId']}（{purchase['type']}・{price['baseTerritory']} {price['customerPrice']:g}）{names}")
        print(f"問題なし: 課金 {len(purchases)} 件")
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
    store = InAppPurchases(client, args.dry_run)

    try:
        app = client.find_app(args.bundle_id or bundle_id())
        print(f"対象: {app['attributes']['name']}（{app['attributes']['bundleId']}）")
        existing = store.existing(app["id"])
        all_territories = store.all_territories()
        for purchase in purchases:
            sync_purchase(store, app["id"], purchase, existing.get(purchase["productId"]), all_territories)
    except ApiError as error:
        if error.status == 403:
            raise SystemExit(
                "App Store Connect API Key の権限が足りないか、「有料 App」の契約が有効になっていません"
                "（課金の編集には Admin か App Manager の役割が要ります）。\n"
                f"{error}"
            ) from None
        raise

    print("完了（dry-run）" if args.dry_run else "完了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
