#!/usr/bin/env python3
"""
署名なしの Archive のアプリに entitlements（Game Center など）の権限を付け、Export した IPA に残ったかを確かめる。

Archive は CODE_SIGNING_ALLOWED=NO で作るので、CODE_SIGN_ENTITLEMENTS の権限がアプリに書き込まれない（.xcent も作られない）。
Export は Archive の中のアプリの署名にある権限を引き継いで署名し直すため、そのままでは権限が無いアプリが App Store Connect に上がる
（Game Center にサインインできない、など）。

使い方:
  # Archive の後・Export の前: entitlements の $(変数) をビルド設定で展開し、その権限でアプリをアドホック署名する
  #（本番の署名は Export がする）。展開した entitlements を OUTPUT に書き出す
  python3 .github/scripts/app-entitlements.py sign \
    --archive build.xcarchive --project MyApp.xcodeproj --scheme MyApp --output entitlements.plist

  # Export の後: IPA のアプリの署名に、entitlements のキーがすべて残っているかを確かめる（値は Export が書き換えることがあるので見ない）
  python3 .github/scripts/app-entitlements.py verify --ipa export/MyApp.ipa --entitlements entitlements.plist

アプリに entitlements が無い（CODE_SIGN_ENTITLEMENTS が空）ときは、sign は何もせず、verify も何も確かめない。
Python の標準ライブラリだけで動く。
"""

import argparse
import json
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

# $(NAME) / ${NAME}。$(NAME:rfc1034identifier) のような修飾子は扱わず、展開できない変数として止める
VARIABLE = re.compile(r"\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]")


def fail(message: str) -> None:
    print(f"::error::{message}")
    sys.exit(1)


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def app_path_in_archive(archive: Path) -> Path:
    with (archive / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    return archive / "Products" / info["ApplicationProperties"]["ApplicationPath"]


def build_settings(project: str, scheme: str, wrapper_name: str) -> dict:
    output = run(
        "xcodebuild", "-showBuildSettings", "-json",
        "-project", project, "-scheme", scheme, "-configuration", "Release", "-sdk", "iphoneos",
    )
    for target in json.loads(output):
        settings = target["buildSettings"]
        if settings.get("WRAPPER_NAME") == wrapper_name:
            return settings
    fail(f"ビルド設定に {wrapper_name} のターゲットが見つかりません")
    return {}


def expand(value, settings: dict, unresolved: set):
    """entitlements の値の $(変数) をビルド設定で展開する。展開できない変数は unresolved に集める"""
    if isinstance(value, str):
        def replace(match: re.Match) -> str:
            name = match.group(1)
            if name in settings:
                return settings[name]
            unresolved.add(name)
            return match.group(0)
        return VARIABLE.sub(replace, value)
    if isinstance(value, list):
        return [expand(item, settings, unresolved) for item in value]
    if isinstance(value, dict):
        return {key: expand(item, settings, unresolved) for key, item in value.items()}
    return value


def sign(args: argparse.Namespace) -> None:
    app = app_path_in_archive(Path(args.archive))
    settings = build_settings(args.project, args.scheme, app.name)
    entitlements_setting = settings.get("CODE_SIGN_ENTITLEMENTS", "")
    if not entitlements_setting:
        print(f"{app.name} に entitlements はありません")
        return

    source = Path(settings["SRCROOT"]) / entitlements_setting
    with source.open("rb") as f:
        entitlements = plistlib.load(f)
    # AppIdentifierPrefix・TeamIdentifierPrefix は署名のときに Xcode が決める値で、-showBuildSettings には出ない
    team_prefix = f"{settings.get('DEVELOPMENT_TEAM', '')}."
    settings = {"AppIdentifierPrefix": team_prefix, "TeamIdentifierPrefix": team_prefix, **settings}
    unresolved: set = set()
    entitlements = expand(entitlements, settings, unresolved)
    if unresolved:
        fail(f"{entitlements_setting} の変数を展開できません: {', '.join(sorted(unresolved))}")

    output = Path(args.output)
    with output.open("wb") as f:
        plistlib.dump(entitlements, f)
    run("codesign", "--force", "--sign", "-", "--entitlements", str(output), str(app))
    print(f"{app.name} を {entitlements_setting} の権限でアドホック署名しました: {', '.join(sorted(entitlements))}")


def signed_entitlements(app: Path) -> dict:
    output = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", "--xml", str(app)], check=True, capture_output=True
    ).stdout
    return plistlib.loads(output) if output.strip() else {}


def verify(args: argparse.Namespace) -> None:
    expected_path = Path(args.entitlements)
    if not expected_path.exists():
        print("entitlements が無いアプリなので、確かめません")
        return
    with expected_path.open("rb") as f:
        expected = plistlib.load(f)

    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(args.ipa) as ipa:
            ipa.extractall(tmp)
        apps = list((Path(tmp) / "Payload").glob("*.app"))
        if len(apps) != 1:
            fail(f"{args.ipa} の Payload にアプリが 1 つではありません（{len(apps)} 個）")
        actual = signed_entitlements(apps[0])

    missing = sorted(set(expected) - set(actual))
    if missing:
        fail(
            f"Export したアプリの署名に、entitlements の権限が入っていません: {', '.join(missing)}。"
            "プロビジョニングプロファイル（App ID の Capability）にその権限があるかを確かめてください"
        )
    print(f"Export したアプリの署名に、entitlements の権限がすべて入っています: {', '.join(sorted(expected))}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    sign_parser = commands.add_parser("sign", help="Archive のアプリを entitlements の権限でアドホック署名する")
    sign_parser.add_argument("--archive", required=True)
    sign_parser.add_argument("--project", required=True)
    sign_parser.add_argument("--scheme", required=True)
    sign_parser.add_argument("--output", required=True, help="展開した entitlements を書き出すパス")
    sign_parser.set_defaults(handler=sign)

    verify_parser = commands.add_parser("verify", help="IPA のアプリの署名に entitlements の権限が残っているか確かめる")
    verify_parser.add_argument("--ipa", required=True)
    verify_parser.add_argument("--entitlements", required=True, help="sign が書き出した entitlements")
    verify_parser.set_defaults(handler=verify)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
