import StoreKit
import SwiftUI

/// きせかえ（タイトルの右上の傘のボタンから開く）。
/// 購入前は、課金「広告なし＋傘のきせかえ」の内容・購入・復元と、鍵のついた傘の見本。購入後は傘を選べる
struct DressUpView: View {
    let onBack: () -> Void

    @Environment(\.purchase) private var purchase
    @AppStorage(UmbrellaSkin.selectedKey) private var selectedRaw = UmbrellaSkin.leaf.rawValue
    @State private var isBusy = false
    @State private var notice: Notice?

    private var store: Store { .shared }

    /// 購入・復元のあとに出すダイアログ
    struct Notice: Equatable {
        let title: String
        let message: String
    }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                ZStack {
                    Text("きせかえ").font(.kRounded(18)).foregroundStyle(Color.ink)
                    HStack {
                        BackButton(action: onBack)
                        Spacer()
                    }
                }
                ScrollView {
                    VStack(spacing: 14) {
                        if !store.isPurchased {
                            premiumCard
                        }
                        skinGrid
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: 420)
        }
        .task { await store.loadProduct() }
        .noticeAlert($notice)
    }

    // MARK: 課金の内容と購入

    private var premiumCard: some View {
        VStack(spacing: 12) {
            Text("広告なし＋傘のきせかえ").font(.kRounded(18)).foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: 6) {
                benefit("広告を見ずに続けられ、りんごも取れます")
                benefit("5 種類の傘のきせかえが使えます")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PillButton(title: purchaseTitle, fill: .kGreen, textColor: .white) {
                Task { await buy() }
            }
            .disabled(isBusy)
            .accessibilityIdentifier("dressup_purchase")
            Button {
                SoundPlayer.shared.play(.button)
                Task { await restore() }
            } label: {
                Text("購入を復元").font(.kRounded(14, .bold)).foregroundStyle(.secondary).padding(6)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("dressup_restore")
        }
        .padding(20)
        .background(.white, in: .rect(cornerRadius: 24))
    }

    private func benefit(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.kGreen)
            Text(text).font(.kRounded(14, .medium)).foregroundStyle(Color.ink)
        }
    }

    private var purchaseTitle: String {
        if isBusy { return String(localized: "お待ちください…") }
        guard let product = store.product else { return String(localized: "購入する") }
        return String(localized: "\(product.displayPrice) で購入")
    }

    private func buy() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if store.product == nil { await store.loadProduct() }
        guard let product = store.product else {
            notice = Notice(
                title: String(localized: "購入できませんでした"),
                message: String(localized: "ネットワークを見直してみてね")
            )
            return
        }
        do {
            switch await store.handle(try await purchase(product)) {
            case .purchased:
                notice = Notice(
                    title: String(localized: "ありがとうございます！"),
                    message: String(localized: "広告なしで遊べるようになり、傘を選べるようになりました")
                )
            case .pending:
                notice = Notice(
                    title: String(localized: "承認を待っています"),
                    message: String(localized: "承認されると、使えるようになります")
                )
            case .failed(let reason):
                notice = Notice(title: String(localized: "購入できませんでした"), message: reason)
            case .cancelled:
                break
            }
        } catch {
            notice = Notice(title: String(localized: "購入できませんでした"), message: error.localizedDescription)
        }
    }

    private func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if let notice = Self.notice(for: await store.restore()) {
            self.notice = notice
        }
    }

    /// 購入を復元した結果のダイアログ（設定画面でも使う）。やめたときは出さない
    static func notice(for outcome: Store.RestoreOutcome) -> Notice? {
        switch outcome {
        case .restored:
            Notice(title: String(localized: "購入を復元しました"), message: String(localized: "広告なしで遊べ、傘を選べます"))
        case .notFound:
            Notice(
                title: String(localized: "復元できる購入がありません"),
                message: String(localized: "購入したときと同じ Apple アカウントでサインインしているか確かめてね")
            )
        case .failed(let reason):
            Notice(title: String(localized: "復元できませんでした"), message: reason)
        case .cancelled:
            nil
        }
    }

    // MARK: 傘の一覧

    /// いま使う傘（購入していなければ葉っぱ）。@AppStorage を読み、選び直したらすぐ描き直す
    private var current: UmbrellaSkin {
        store.isPurchased ? UmbrellaSkin(rawValue: selectedRaw) ?? .leaf : .leaf
    }

    private var skinGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(UmbrellaSkin.allCases) { skin in
                skinCell(skin)
            }
        }
        .padding(14)
        .background(.white.opacity(0.9), in: .rect(cornerRadius: 24))
    }

    private func skinCell(_ skin: UmbrellaSkin) -> some View {
        let locked = !skin.isFree && !store.isPurchased
        let selected = skin == current
        return Button {
            guard !locked else { return }
            SoundPlayer.shared.play(.button)
            selectedRaw = skin.rawValue
        } label: {
            VStack(spacing: 4) {
                Image(ItemKind.piglet.textureName(.normal, skin: skin))
                    .resizable()
                    .scaledToFit()
                    .frame(height: 76)
                    .opacity(locked ? 0.45 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Color(hex: 0x9A8F86), in: Circle())
                        }
                    }
                Text(skin.title).font(.kRounded(13, .bold)).foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? Color.kGreen.opacity(0.18) : Color.clear, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.kGreen : .clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("skin_\(skin.rawValue)")
        .accessibilityValue(Text(selected ? String(localized: "選択中") : (locked ? String(localized: "購入すると使えます") : "")))
    }
}

extension View {
    /// 購入・復元の結果のダイアログ（OK で閉じる）
    func noticeAlert(_ notice: Binding<DressUpView.Notice?>) -> some View {
        alert(
            notice.wrappedValue?.title ?? "",
            isPresented: Binding(get: { notice.wrappedValue != nil }, set: { if !$0 { notice.wrappedValue = nil } }),
            presenting: notice.wrappedValue
        ) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.message)
        }
    }
}
