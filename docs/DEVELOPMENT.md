# 技術構成と開発ガイド

ドパギキ ToDoの実装・検証に関する情報です。アプリの特徴は[README](../README.md)、環境構築とiPhoneへのインストールは[セットアップ](SETUP.md)を参照してください。

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

## 主要機能の実装

### Screen Time

FamilyControls / ManagedSettings / DeviceActivityを使用して、今日のマストが未完了の間は選択したアプリを制限します。全マスト達成後の解除、15分の一時解除、翌日の再制限に対応します。署名・権限の設定と実機確認の手順は[Screen Timeを含む通常版](SETUP.md#screen-timeを含む通常版)を参照してください。

### 触覚・音・表示

Core Hapticsで23種類の触覚を使い分け、星の着地では音と振動の開始を同期します。「最大（100%）」はAPI上限の強度です。対応端末や持ち方により体感は変わるため、実機で確認してください。

画面はSwiftUI、星・メダルの演出はSceneKitで実装しています。iOS 26以降は主要な操作部分にLiquid Glassを使用します。旧OSやアクセシビリティ設定に応じた表示にも対応しています。

### 保存領域

通常版はApp Group、無料Personal Team確認版はアプリ専用領域を使用します。Bundle Identifierと保存領域が異なるため、両者のデータは自動移行しません。利用者向けの説明は[データの取り扱い](../Distribution/Privacy.md)を参照してください。

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

## 素材と配布準備

アイコン・メダル・背景は画像生成素材で、[生成プロンプト](../Design/GeneratedAssets.json)を記録しています。着地音は[同梱スクリプト](../scripts/generate_star_sounds.py)で合成しています。外部の3Dモデルは使用していません。

[TestFlightの準備手順](../Distribution/TestFlight.md)、[ベータメタデータ](../Distribution/BetaMetadata.json)、[アップロード前の確認](REPOSITORY_REVIEW.md)を用意しています。TestFlightの署名付き配布・アップロード・招待発行は未実施です。

[READMEに戻る](../README.md)
