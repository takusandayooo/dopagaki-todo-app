<div align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="ドパギキのアプリアイコン">
  <h1>ドパギキ ToDo</h1>
  <p><strong>やることに集中。達成は、手に響く。</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Swift-F05138?style=for-the-badge&amp;logo=swift&amp;logoColor=white" alt="言語：Swift">
    <img src="https://img.shields.io/badge/SwiftUI-007AFF?style=for-the-badge&amp;logo=swift&amp;logoColor=white" alt="UI：SwiftUI">
    <img src="https://img.shields.io/badge/Python-3-3776AB?style=for-the-badge&amp;logo=python&amp;logoColor=white" alt="補助スクリプト：Python 3">
  </p>
  <p>
    <img src="https://img.shields.io/badge/iOS-17%2B-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="対象OS：iOS 17以降">
    <img src="https://img.shields.io/badge/Xcode-26%2B-147EFB?style=for-the-badge&amp;logo=xcode&amp;logoColor=white" alt="開発環境：Xcode 26以降">
    <img src="https://img.shields.io/badge/Swift_Package-local-F05138?style=for-the-badge&amp;logo=swift&amp;logoColor=white" alt="ローカルSwift Package">
  </p>
</div>

**Screen Timeで選んだアプリを「今日のマスト」達成まで制限し、達成した瞬間を触覚フィードバックで祝うiPhoneアプリです。**

取りかかる前は、気が散るアプリを制限してやることに集中する。取り組んでいる間は、チェックやタイマーの操作が手に返る。やりきったら、星の着地やレベルアップの振動とともに、選んだアプリが使えるようになる。この「集中するための制限」と「達成を感じる触覚」が、ドパギキの中心です。

**[セットアップ](docs/SETUP.md) · [製品仕様](SPEC.md) · [TestFlight準備](Distribution/TestFlight.md) · [アップロード前の確認](docs/REPOSITORY_REVIEW.md)**

## マスト達成まで、選んだアプリを制限

「今日、必ずやること」をマストに設定し、Screen Timeで自分が選んだアプリを制限します。今日のマストをすべて完了すると制限が解除され、次の再制限時刻まで使えるようになります。

1. 今日のタスクを作り、必ず終えたいものを「マスト」にする。
2. Screen Timeの利用を許可し、集中中に制限したいアプリを選ぶ。
3. 「マスト完了までアプリを制限」をオンにして、タスクに取り組む。
4. 今日のマストをすべて完了すると、選んだアプリの制限が解除される。

マストがない日は制限しません。必要なときは15分の一時解除を利用でき、Screen Timeの許可は本人が取り消せます。翌日の再制限時刻も設定できます。

> **Screen Timeの実機確認には、Apple Developer Programの開発チームとFamily Controls権限が必要です。** 無料Personal Teamの確認版にはアプリ制限を含みません。制限・解除の実装はありますが、実機での動作検証は未完了です。[Screen Time対応版のセットアップ](docs/SETUP.md#screen-timeを含む通常版)

## 操作と達成を、触覚で感じる

触覚フィードバックは、日々の操作からタスク完了まで使い分ける**23パターン**。振動の長さ・リズム・鋭さを変え、ボタンを押した手応えや「やりきった」感覚が手に伝わるようにしています。

| 場面 | 触覚の体験 |
| --- | --- |
| 日付・時刻・目標時間を選ぶ | 値が切り替わるたびに、刻むような手応え |
| チェック・タスク保存 | 入れる／外す／全完了を異なるリズムで通知 |
| 集中タイマー | 開始・一時停止・再開・延長・目標到達をそれぞれ区別 |
| 星が着地する | 着地の瞬間に音と振動を開始し、星ごとに異なる余韻 |
| レベルアップ | 「ドン、ドン、ドーン」と約1.91秒の3連振動 |
| メダル・マスト全達成 | それぞれ専用の振動で達成を祝う |

**「設定 → 振動を試す」で全パターンを体験できます。**「最大（100%）」ではAPI上限の強度で再生し、標準・弱・オフにも切り替えられます。星の着地音は「達成の音」をオンにすると有効です。

触覚は対応iPhoneで確認してください。無料Personal Teamの確認版でも試せます。星・XP・メダル・紙吹雪は、この手応えに合わせた視覚的なお祝いです。

<p align="center">
  <img src="Design/Verification/CompletionBackground.png" width="240" alt="星とXPで祝うタスク完了画面">
  <img src="Design/Verification/MedalCollection.png" width="240" alt="記録とメダルコレクション">
</p>

画像はシミュレーターの検証用データです。初回起動時にサンプルのタスクや実績は入りません。

## 集中と達成を支える機能

| 機能 | 内容 |
| --- | --- |
| タスク・習慣 | 期限、優先度、今日のマスト、チェックリスト、ラベル、毎日・曜日・毎月の繰り返し |
| 集中時間 | ストップウォッチ／タイマー、一時停止・再開・延長、時間だけの保存 |
| 達成の可視化 | 立体の星、XP、レベルアップ、紙吹雪・花火 |
| 記録・実績 | 活動カレンダー、連続記録、6種類のメダル、写真・テキスト・音声からのメモ |
| リマインダー | 期限・声かけ・タイマー終了のローカル通知 |

画面はSwiftUI、星・メダルの演出はSceneKitで実装しています。iOS 26以降は主要な操作部分にLiquid Glassを使用します。旧OSやアクセシビリティ設定に応じた表示にも対応しています。

## 使用技術

| 種別 | 言語・技術 | 用途 |
| --- | --- | --- |
| アプリの言語 | Swift | 画面、タスク・集中時間・報酬のロジック、iOS拡張 |
| アプリ制限 | FamilyControls / ManagedSettings / DeviceActivity | Screen Timeによるマスト達成までの制限・解除・翌日の再制限 |
| 触覚・音 | Core Haptics / AVFAudio | 23種類の触覚、星の着地音との同期 |
| UI | SwiftUI / Liquid Glass | タスク・タイマー・実績画面、iOS 26以降の操作部分 |
| 立体演出 | SceneKit | 星とメダルの表示・アニメーション |
| 音声・写真 | Speech / PhotosUI | 音声からのメモ入力、選択した写真の添付 |
| 通知 | UserNotifications | 期限・声かけ・タイマー終了のローカル通知 |
| データ保存 | Codable / JSON / FileManager | 端末内のタスク・記録・写真の保存 |
| パッケージ・テスト | Swift Package Manager / XCTest | ローカルの中核ロジックと25項目のテスト |
| 開発用スクリプト | Python 3 | Xcodeプロジェクト・配布準備、構成検査、効果音の合成 |

アプリ本体はSwiftで実装しています。Pythonは開発作業の補助に使い、iPhone上でPythonを実行する構成ではありません。

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

## まず動かす

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

**自分のiPhoneに入れる場合は [セットアップ手順](docs/SETUP.md) へ。** 無料Personal Teamの確認版、Screen Time対応版、初回接続、Wi-Fi更新、署名期限の更新を説明しています。

## 最初に試す操作

1. 実機の「設定 → 振動を試す」で23パターンを試し、触覚の強さを選ぶ。
2. 「今日」からタスクを作成し、必ず終えたいものをマストにする。
3. Screen Time対応版では、利用を許可して対象アプリを選び、マスト完了までの制限を有効にする。
4. タスクに取り組み、チェックやタイマー操作の手応えを確かめる。
5. タスクを完了して、星の着地・レベルアップの振動を体験する。Screen Time対応版では、全マスト達成後の解除も確認する。
6. 音も使う場合は「達成の音」をオンにする。音は初期オフで、サイレントモードに従う。

通常の文字サイズでは完了画面のスクロールを不要にし、特大文字では全操作に届くようスクロールを許可しています。演出はスキップでき、「動きを減らす」設定にも対応しています。

触覚は実機で確認してください。最大設定でも、持ち方や端末によって感触は変わります。[演出の確認動画](Design/Verification/CompletionFireworks.mp4)はシミュレーターの映像、[着地音の試聴](Design/Verification/StarImpactPreview.mp3)は生成した効果音です。

## 保存とプライバシー

- タスク・集中時間・メモ・取り込んだ写真は端末内に保存します。ログイン・クラウド同期・独自の解析SDKはありません。
- 通常版はApp Group、無料確認版はアプリ専用領域を使用します。両者のデータは自動移行しません。
- 音声入力は端末内認識を優先します。非対応の場合はAppleの音声認識サービスを使用します。録音ファイル自体は保存しません。
- 音声・通知・Screen Timeを許可しなくても、手入力のToDoと集中記録は利用できます。
- iOSの設定により記録がバックアップに含まれる場合があります。アプリ内には全データの一括削除・書き出し機能はありません。

詳しくは [データの取り扱い](Distribution/Privacy.md) を参照してください。この文書は配布準備用の草案で、公開時には問い合わせ先などを確定する必要があります。

## 開発とテスト

```sh
# 中核ロジック・保存処理の確認
swift run DopagakiChecks

# XCTest（Xcodeのツールチェーンを使用）
swift test

# Swift構文、プロジェクト参照、リソースの確認
python3 scripts/check_project.py

# Gitのステージに含めたファイルの秘密情報・個人設定の簡易検査
python3 scripts/check_repository.py
```

25項目の中核・保存テスト、シミュレーター向けビルド、Personal Team版のiPhoneへのインストール・起動を確認しています。Screen Timeの実機制限・解除とTestFlightへの配布は未検証・未実施です。触覚の体感やLiquid Glassの全画面の見え方は、対応実機での確認を続けます。

| ディレクトリ | 役割 |
| --- | --- |
| `App/Views` | タスク、タイマー、記録、設定のSwiftUI画面 |
| `App/Celebrations` | 完了画面・星・紙吹雪・花火 |
| `App/Services` | 触覚、音声認識、通知、Screen Time |
| `Core` / `CoreTests` | タスク・実行分・報酬・集中時間のロジックとテスト |
| `Shared` / `PersistenceTests` | 保存・拡張との共有とテスト |
| `Extensions` | 日次監視、制限画面、制限画面の操作 |
| `scripts` | ビルド準備、構成検査、効果音生成 |
| `Design` | 生成素材の記録とシミュレーター検証素材 |
| `Distribution` | TestFlight準備手順・審査メモ・プライバシー草案 |

Swiftファイルの追加・削除後に再生成する場合は `python3 scripts/generate_project.py` を使います。**署名・識別子・Info.plist・Entitlementsなども生成し直すため、手動設定がある場合は変更内容を確認してください。**

## 配布状況と素材

ソースコードをGitHubで公開しています。TestFlight／App Storeへのアプリ配布は別です。[TestFlightの準備手順](Distribution/TestFlight.md)と[ベータメタデータ](Distribution/BetaMetadata.json)を用意していますが、署名付き配布・アップロード・招待発行は未実施です。

アイコン・メダル・背景は画像生成素材で、[生成プロンプト](Design/GeneratedAssets.json)を記録しています。着地音は[同梱スクリプト](scripts/generate_star_sounds.py)で合成しています。外部の3Dモデルは使用していません。

利用・再配布のライセンスは未設定です。コードや素材を第三者が利用・再配布する場合は、権利者への確認が必要です。
