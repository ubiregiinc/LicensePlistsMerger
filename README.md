# LicensePlistsMerger

[CocoaPods](https://github.com/CocoaPods/CocoaPods/wiki/Acknowledgements)や[LicenseList(SourcePackagesParser)](https://github.com/cybozu/LicenseList)が生成したライセンス表示用plistをマージするツールです。

表示は[LicensePlist](https://github.com/mono0926/LicensePlist)のスタイルをリスペクトしています。

# Why LicensePlistsMerger？

CocoaPodsやSwift Package Managerのライブラリのライブラリ表示を行うためのツールはあるが、その両方に対応するものは少ない。

その上で、オフラインで処理が完結するものが見つけられなかったため作成した。

# Usage

```
git clone https://github.com/ubiregiinc/LicensePlistsMerger.git
cd LicensePlistsMerger
swift run license-plists-merger --cocoapods-plist-path Pods-Acknowledgements.plist --license-list-plist-path license-list.plist -o Acknowledgements.plist
```
