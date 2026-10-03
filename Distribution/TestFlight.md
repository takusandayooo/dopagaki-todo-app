# ドパガキ ToDo：TestFlight 配布準備

更新日：2026-10-03。これは現在の実装に対応する配布手順と説明文の下書きです。アップロード、Appleの権限承認、外部テストの審査、招待の送信が完了したことを示すものではありません。

## 1. 配布前に本人が設定する項目

| 項目 | 現在の記入状態・対応 |
| --- | --- |
| Apple Developer Program | **配布チーム未設定**。利用するチームのメンバーシップを確認して進める。無料のPersonal Team確認版はTestFlight用の配布版に使用しない |
| 開発チームID・配布用Bundle ID | 未入力。アプリ本体と3拡張機能の識別子を確定する |
| App Group | 全7ターゲットで同じ、自分のチームに登録した識別子を使用する |
| App Store Connectのアプリ | 未確認。配布用Bundle IDに対応するアプリレコードを作成する |
| Family Controls配布権限 | Appleの承認状態を本体と3拡張機能すべてで確認する |
| バージョン・ビルド番号 | 配布コピーで設定する。次のアップロードではビルド番号を更新する |
| フィードバック用メール | **未入力：本人が記入** |
| 審査連絡先の氏名・メール・電話 | **すべて未入力：本人が記入** |
| プライバシーポリシーURL | **未入力：本人が公開URLを設定**。文章の元は [Privacy.md](Privacy.md) |
| 暗号化・輸出コンプライアンス | 現行実装に合わせて `ITSAppUsesNonExemptEncryption=false` を設定済み。実装変更時に再確認する |

TestFlightを利用する配布にはApple Developer Programのメンバーシップが必要です。[Apple Developer Program](https://developer.apple.com/programs/)

Family Controlsの配布申請はAccount Holderが行います。このプロジェクトでは `Dopagaki` 本体に加え、`ActivityMonitor`、`ShieldConfiguration`、`ShieldAction` の3拡張機能にも申請が必要です。本体の承認だけで完了したと判断せず、各配布用識別子・プロビジョニングプロファイルへ権限が反映されたことを確認します。[AppleのFamily Controls申請手順](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

配布権限が未承認のままScreen Time入りのビルドをTestFlightへ出すことは、この手順では扱いません。Screen Timeを含めない無料実機確認版と、本体・拡張機能を含むTestFlight配布版は分けてください。

## 2. ビルド・アップロード

1. 登録後、本人のTeam IDと登録した識別子を使って配布コピーを生成します。`YOUR_TEAM_ID` は10文字の実際のTeam ID、`jp.yourname.dopagaki` とApp Groupは自分の登録値へ置き換えます。

   ```sh
   python3 scripts/prepare_testflight.py --help
   python3 scripts/prepare_testflight.py \
     --team YOUR_TEAM_ID \
     --bundle-id jp.yourname.dopagaki \
     --app-group group.jp.yourname.dopagaki \
     --build-number 1 \
     --output /private/tmp/dopagaki-testflight
   ```

   元プロジェクトは変更しません。生成先は元workspaceの外の空のディレクトリにしてください。全7ターゲットとCoreパッケージをコピーし、設定結果を `testflight-preparation.json` に保存します。バージョンは現行の1.0を保持し、指定したビルド番号を本体・全拡張に揃えます。バージョンを変更する場合は、全7ターゲットの `Info.plist` の `CFBundleShortVersionString` と `MARKETING_VERSION` も揃えます。次回は新しい生成先と未使用のビルド番号を指定します。

2. 生成先の `Dopagaki.xcodeproj` をXcode 26以降で開き、通常版の `Dopagaki` スキームを選びます。全7ターゲットのSigning & Capabilitiesで同じチームとApp Groupを確認します。Family Controlsの配布権限は本体とScreen Timeの3拡張で確認します（iPhone・WatchのウィジェットとWatch本体には不要）。権限未承認の状態では署名・アップロードへ進めません。
3. 実機向けのRelease Archiveを作成します。Organizerで署名・アプリ本体・拡張機能・バージョンを確認し、Validate後にApp Store Connectへアップロードします。外部テストも予定する場合は **TestFlight Internal Onlyを選ばず**、通常のApp Store Connect配布を選びます。[Appleの外部テスト手順](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
4. App Store Connect側の処理完了を待ち、暗号化に関する質問など未処理項目へ回答します。
5. [BetaMetadata.json](BetaMetadata.json) の説明、What to Test、審査メモを転記します。`null` のフィードバックメール・審査連絡先・公開URLは本人の情報で埋めます。このJSONは転記用の下書きで、アップロードAPIへそのまま送るリクエストではありません。[Appleのテスト情報入力手順](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)

この準備コマンドはApple会員登録・権限申請・App Store Connectへのアップロード・審査提出・招待メール送信を代行しません。

`PrivacyInfo.xcprivacy` はアプリに同梱します。触覚の連打抑制に使う起動後の経過時間APIについて、`SystemBootTime / 35F9.1` を申告しています。現行版は独自の暗号化処理や外部ライブラリを使わず、暗号化の宣言はAppleの基準に沿って設定しています。[Appleの暗号化宣言の説明](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)

## 3. 自分用・少人数テストの始め方

まずApp Store ConnectのTestFlightで内部グループ「自分用テスト」を作成し、アクセス権のある自分のApp Store Connectユーザーと処理済みビルドを追加します。内部テスターはアプリへアクセスできるApp Store Connectユーザーで、上限は100人です。一般の友人を内部テスターにするためだけに管理用アカウントを付与する必要はありません。[Appleの内部テスター追加手順](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)

友人などApp Store Connectユーザーではない人には、内部グループ作成後に外部グループ「少人数ベータ」を作り、ビルドを追加してTestFlight App Reviewへ提出します。外部向けの初回ビルドには審査が必要です。承認後、同意を得た相手をメールアドレスで招待します。外部テスター上限は10,000人です。今回の下書きには送信済みの招待や公開リンクはありません。[Appleの外部テスター招待手順](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)

テスターはiPhoneにTestFlightを入れ、届いた招待から参加します。1ビルドのテスト可能期間はアップロードから最大90日で、期限後も続ける場合は新しいビルドを用意します。[AppleのTestFlight概要](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## 4. ベータ説明文（転記用）

ドパガキ ToDoは、やること・習慣・集中時間を記録するiPhoneアプリです。タスクを終えると、大きな立体の星、触覚、XPで達成を振り返れます。

毎日・曜日・毎月のタスク、今日のマスト、チェックリスト、ストップウォッチとタイマーに対応。音声からのメモ入力と写真、緑の活動カレンダー、連続記録、メダルで取り組みを残せます。希望する人はScreen Timeを許可して、マスト完了まで選んだアプリを制限できます。

アプリ内のログインは不要です。記録は端末に保存し、クラウド同期はありません。音声入力、通知、アプリ制限を許可しなくても、手入力のToDoと集中記録を利用できます。ベータでは操作の分かりやすさ、保存の安定性、星の動きと触覚の感触を確認しています。

## 5. What to Test（転記用）

- タスクを追加・編集し、今日のマストやチェックリスト、繰り返しが意図どおりに使えるか。
- ストップウォッチ／タイマーを開始し、一時停止・再開・延長、「時間だけ保存して終了」と「タスクを完了」を使い分けられるか。
- 完了時の大きな星、XP、レベル、メダル、マスト全達成が分かりやすいか。設定の「振動を試す」で強さ・長さを確認し、音オン、スキップ、動きを減らす設定も試してください。
- 音声を文字にして修正・保存できるか、写真を添付・表示できるか。許可を拒否した場合も手入力が使えるか。
- 保存した時間とタスク完了が活動カレンダーへ反映され、日付を選ぶと内訳が見られるか。再起動後にタスク・XP・時間・メモが残るか。
- Screen Timeを希望する場合のみ、許可→対象選択→有効化→マスト完了による解除、15分の一時解除を確認してください。再制限時刻の動作はOSの影響を受けるため、前後の状態も報告してください。

不具合の報告には、iPhoneの機種・iOS・ビルド番号・操作手順・期待した結果・実際の結果を添えてください。触覚は「強さ」「長さ」「星の着地とのタイミング」を教えてください。スクリーンショットには個人のタスクや写真が映る場合があるため、共有前に内容を確認してください。

## 6. 審査手順（ログイン不要）

1. アプリを起動します。アカウント作成・ログイン・課金は不要です。初期データは空です。
2. 「今日」右上の追加ボタンから「英語を5分」のようなタスクを作成し、マストタスクをオンにして保存します。
3. タスク詳細の「編集」からチェックリスト項目を追加して保存し、詳細で完了を切り替えます。「このタスクを始める」からストップウォッチを開始し、一時停止・再開後に「時間だけ保存して終了」を選びます。タスクは未完了のまま、保存時間が記録に残ります。
4. 別の計測ではタイマーを選び、短い時間を設定して一時停止・再開・延長を確認します。タイマー終了だけでタスクは完了しません。
5. タスク詳細の「計測せずに完了」、または計測画面の「タスクを完了」を選びます。期限なしの場合は3つの星・100XPを付与します。累計250XPでレベルが上がり、初回完了では「最初の一歩」メダルを獲得します。完了画面のスキップでも保存結果は同じです。
6. 完了画面の「話して記録する」、またはタスク詳細の記録欄を開きます。「話して入力」でマイク・音声認識を許可すると発話を文字にできます。認識文字は保存前に編集できます。許可を拒否してもテキストを入力して保存できます。「写真を追加」で写真を選び、記録します。
7. 「記録・実績」で活動カレンダーと日別内訳、メダルを確認します。アプリを終了して起動し直し、保存内容とXPが残り、重複加算されないことを確認します。
8. アプリ制限は任意です。「設定」→「マストとアプリ制限」でScreen Timeを許可し、対象アプリを選択し、有効化します。未完了マストがある間に対象アプリへ制限画面が出て、マストをすべて終えると解除されることを確認します。必要なら15分だけ一時解除できます。
9. Screen Timeの許可を拒否または取り消した状態でも、タスク作成・集中計測・完了・記録の基本機能を利用できます。マストが0件の日は制限しません。

Screen Time関連は、配布用Family Controls権限を持つ実機ビルドで確認してください。シミュレーターで許可や触覚が使えないことを、本体機能の故障と混同しないようにしてください。

## 7. 既知の制限・ベータで確認する点

- iPhone縦向け・iOS 17以降。iOS 26以降は一部のバーと操作にLiquid Glassを使用します。OSごとの表示・大きな文字サイズは引き続き確認対象です。
- ログイン、クラウド同期、データの書き出し、アプリ内の独立したバックアップ機能はありません。Personal Team確認版と通常配布版ではBundle ID・保存領域が異なるため、記録は自動移行しません。
- 音声は対応端末で端末内認識を優先し、非対応の場合はAppleの音声認識サービスを利用します。許可、通信、言語・端末対応により利用できない場合があります。音声ファイル自体は保存しません。
- 音は初期オフで、サイレントモードに従います。触覚の100%表示はAPI指定強度の上限で、全端末で同じ体感になる保証はありません。実機での長さ・強さ・着地との同期は調整対象です。
- 通知はローカル通知です。予約は次の7日分をアプリ操作で更新します。長期間アプリを開かない場合は予約を延長しません。集中モード・通知許可などにより到達や表示時刻は変わります。
- Screen Timeの許可は本人が取り消せます。絶対に解除できないロックではありません。翌日の再制限と一時解除終了のコールバックもOSの動作に依存し、設定時刻ぴったりの切り替えは保証しません。実機での権限・制限・解除・日またぎを確認してください。
- 期限内または期限なしは3つ星100XP、24時間以内の遅れは2つ星70XP、それ以降は1つ星50XPです。繰り返しタスクは日ごとの実行分として評価します。過去の未完了の繰り返しは今日へ自動繰り越ししません。

## 8. 転記前の連絡先チェック

`BetaMetadata.json` の `feedbackEmail` と `betaReviewContact` は未入力です。本人が連絡を受けられる実情報を入れてから、App Store Connectへ提出してください。`privacyPolicyURL` は [Privacy.md](Privacy.md) を公開した実URLを指定します。ローカルMarkdownへのパスは公開URLの代わりにはなりません。

アプリには「設定 → このアプリについて → プライバシー」の説明画面を追加済みです。運営者・問い合わせ先・TestFlight情報の保持期間を確定して公開ポリシーを仕上げる際に、アプリ内の説明も更新します。
