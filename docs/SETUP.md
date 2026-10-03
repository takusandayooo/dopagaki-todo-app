# セットアップ

アプリの特徴は[README](../README.md)、使用技術・テスト・コード構成は[開発ガイド](DEVELOPMENT.md)を参照してください。

## 必要な環境

| 項目 | 条件 |
| --- | --- |
| 開発環境 | Xcode 26以降を実行できるMac。検証環境はXcode 27 |
| 対象OS | iOS 17以降。Liquid GlassはiOS 26以降 |
| 補助スクリプト | Python 3（標準ライブラリのみ） |
| シミュレーター | Apple開発チームの署名なしでビルド可能 |
| 実機で音・触覚を確認 | Apple Account、開発者モードを有効にしたiPhone。無料Personal Team対応版あり |
| Screen Timeの実機確認 | Apple Developer Programの開発チームとFamily Controls権限 |

外部Swiftパッケージ、サーバー、APIキー、`.env`の設定は不要です。`DopagakiCore`は同じリポジトリ内のローカルSwift Packageです。

## どの方法で動かすか

| 目的 | 方法 | Apple開発チーム |
| --- | --- | --- |
| 画面・タスク・保存を確認 | iPhoneシミュレーター | 不要 |
| 自分のiPhoneで音・触覚を確認 | Personal Team確認版 | 無料Apple Accountで可 |
| 他アプリの制限・解除を確認 | 通常版＋Family Controls | Apple Developer Programが必要 |
| TestFlightで配布 | 配布用の独立コピー | 配布署名・Family Controls配布権限が必要 |

Xcode 26以降、Python 3を用意します。Xcodeは一度起動して初回設定を済ませ、必要なiOS Simulatorランタイムをインストールしてください。

```sh
xcodebuild -version
xcode-select -p
python3 --version
```

複数のXcodeがある場合は、Xcodeの「Settings → Locations → Command Line Tools」で使用するバージョンを選びます。

## リポジトリの取得とシミュレーター

リポジトリをクローンします。

```sh
git clone https://github.com/takusandayooo/dopagaki-todo-app.git
cd dopagaki-todo-app
open Dopagaki.xcodeproj
```

Xcodeで **Dopagaki** スキームとiPhoneシミュレーターを選択し、Runを実行します。プロジェクトは同梱済みのため、初回の再生成は不要です。

コマンドラインでのビルド確認：

```sh
xcodebuild -project Dopagaki.xcodeproj -scheme Dopagaki \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/dopagaki-simulator-build \
  CODE_SIGNING_ALLOWED=NO build
```

触覚・Screen Timeの実際の制限は実機で確認してください。

## 無料Personal TeamでiPhoneに入れる

この確認版はScreen Timeとその3拡張、App Group権限を含みません。ToDo・計測・達成演出・音・触覚は利用できます。通常版と別のBundle Identifierを使用し、記録は自動移行しません。

### 1. Apple AccountとiPhoneを準備

1. Xcodeの「Settings → Apple Accounts」で自分のApple Accountにサインインします。
2. iPhoneをMacにケーブル接続し、ロックを解除します。
3. iPhoneに「このコンピュータを信頼」が表示されたら、内容を確認して本人が承認します。
4. Xcodeの端末管理画面でペアリングを確認します。Xcode 27ではDevice Hub、それ以前はDevices and Simulatorsを使用します。
5. iPhoneの「設定 → プライバシーとセキュリティ → デベロッパモード」を有効にし、表示された再起動・確認を完了します。

### 2. Team IDと端末IDを確認

Team IDはXcodeの署名画面や開発アカウントで確認します。端末IDは次の一覧の**実機**のIdentifierを使用します。

```sh
xcrun devicectl list devices
```

以下の `YOUR_TEAM_ID` と `YOUR_IPHONE_UDID` を自分の値に置き換えます。値や署名ファイルをREADMEやGitに書き戻す必要はありません。

### 3. 確認版を生成・ビルド

```sh
python3 scripts/prepare_personal_device.py \
  --output /tmp/dopagaki-personal-device \
  --team YOUR_TEAM_ID

xcodebuild \
  -project /tmp/dopagaki-personal-device/Dopagaki.xcodeproj \
  -scheme Dopagaki -configuration Debug \
  -destination 'id=YOUR_IPHONE_UDID' \
  -derivedDataPath /tmp/dopagaki-personal-build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

元のプロジェクトは変更せず、別のプロジェクトを生成します。生成物にはローカルの絶対パスとTeam IDが含まれるため、リポジトリの外に置いてください。出力先はこの作業専用のディレクトリを指定します。

### 4. インストール・起動

```sh
xcrun devicectl device install app \
  --device YOUR_IPHONE_UDID \
  /tmp/dopagaki-personal-build/Build/Products/Debug-iphoneos/Dopagaki.app

xcrun devicectl device process launch \
  --device YOUR_IPHONE_UDID dev.dopagaki.todo.personal
```

初回に開発元の信頼が必要な場合は、iPhoneの「設定 → 一般 → VPNとデバイス管理」で自分のデベロッパAppを確認し、本人が信頼操作を行ってから再度起動します。

### 5. Wi-Fiで更新

ペアリング後、MacとiPhoneを同じネットワークにつなぎます。端末管理画面に「Connect via network」がある場合は有効にします。ケーブルを外し、iPhoneをロック解除して接続を確認します。

```sh
xcrun devicectl device info details --device YOUR_IPHONE_UDID
```

`Transport Type: localNetwork` がWi-Fi側で確認した接続です。その状態でビルド・インストール・起動を繰り返します。接続できない場合は、まずケーブル接続で確認してください。

### 署名期限を更新する

無料Personal Teamの署名は通常約7日で期限切れになります。同じApple Account・Bundle Identifierで新しい開発用署名を使ってビルドし、上書きインストールします。期限切れ前でも後でも更新できます。上書き更新では通常アプリの記録は保持されますが、**アプリを削除するとデータを失うため、削除してから入れ直す操作は避けてください。**

## Screen Timeを含む通常版

無料Personal TeamではFamily Controlsを署名できません。Apple Developer Programの開発チームを使用します。

1. `Dopagaki.xcodeproj` の4ターゲット（Dopagaki、ActivityMonitor、ShieldConfiguration、ShieldAction）に同じ開発チームを設定します。
2. Bundle Identifierを自分のチームで使える値に設定します。各拡張は本体の識別子に拡張名を付けた形にします。
3. 全ターゲットでFamily Controlsと同一のApp Groupを有効にします。Build Settingsの `DOPA_APP_GROUP` も一致させます。
4. 実機を選びRunします。手元の署名設定はそのままGitにコミットせず、差分を確認してください。

テストは「Screen Timeを許可 → 対象アプリを選択 → マスト未完了で制限 → 全完了で解除」の順に行います。15分の一時解除、翌日の再制限、OS側で許可を取り消した場合も確認します。時刻コールバックはOSの状態に依存し、厳密な定刻実行は保証しません。

自分の実機で開発テストする権限と、TestFlight／App Storeへ配布する権限は別です。配布には本体と各拡張のFamily Controls配布権限が必要です。[Appleの設定ガイド](https://developer.apple.com/documentation/xcode/configuring-family-controls)・[配布権限](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

## TestFlight

[配布手順](../Distribution/TestFlight.md)に従い、`prepare_testflight.py`で独立コピーを作ります。元の作業フォルダの外にある空の出力先を使い、実際のTeam ID・Bundle ID・App Group・ビルド番号を指定します。

署名、権限、公開プライバシーポリシー、問い合わせ先、App Store Connectへの登録を揃えてからValidate／Uploadします。GitHubにソースを保存しても、TestFlightへのアップロードは行われません。

## 困ったとき

| 状況 | 確認すること |
| --- | --- |
| Personal TeamでFamily Controlsの署名に失敗 | 無料確認版の生成プロジェクトを開いているか |
| iPhoneが一覧にない | ロック解除、同じWi-Fi、初回ペアリング。ケーブル接続でも確認 |
| 起動時に信頼／署名エラー | デベロッパモード、開発元の信頼、署名期限 |
| Bundle Identifierが使用できない | 通常版の識別子を自分のチームのものに変更。無料確認版は生成先のBuild Settingsで本体IDを調整し、起動コマンドも同じIDを使う |
| 音が出ない | アプリの「達成の音」、端末音量、サイレントモード |
| 触覚を感じない | 実機か、アプリの触覚設定がオフでないか。「振動を試す」で確認 |
| 無料確認版から通常版へ記録が移らない | Bundle Identifierと保存領域が異なる。現行版に自動移行はない |
| Xcodeを再生成したら署名設定が消えた | 生成処理は設定ファイルも初期化する。Git差分を見て個人設定を戻す |

[READMEに戻る](../README.md)
