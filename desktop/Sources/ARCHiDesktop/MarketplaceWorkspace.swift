import SwiftUI

/// Local design exchange through the existing companion, renderer and profile.
@MainActor
struct MarketplaceWorkspace: View {
    @ObservedObject var store: CompanionStore
    private enum Page: String, CaseIterable, Identifiable {
        case discover = "Discover", collection = "My items", create = "Create"
        var id: String { rawValue }
    }
    @State private var page: Page = .discover
    @State private var query = ""
    @State private var selected: CompanionItemPackage? = CompanionItemCatalog.designs.first
    @State private var draft = CompanionItemPackage.creatorDefault
    @State private var removal: CompanionItemPackage?
    private enum ImportHandoff {
        case variation(CompanionItemPackage), workTogether(CompanionItemPackage)
    }
    @State private var importHandoff: ImportHandoff?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                outfit
                Picker("Marketplace section", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("marketplace.sections")
                if page == .create { creator }
                else {
                    HStack {
                        TextField("Find a design or creator", text: $query)
                            .textFieldStyle(.roundedBorder).accessibilityIdentifier("marketplace.search")
                        Button("Import recipe", systemImage: "square.and.arrow.down") { store.importMarketItem() }
                            .accessibilityIdentifier("marketplace.import")
                    }
                    if filteredItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(page == .collection && query.isEmpty ? "Room for your first item." : "No matching designs.").font(.headline)
                            Text("Choose a design in Discover, or make a staff in Create. Adding keeps a local recipe; equipping is your next choice.")
                                .foregroundStyle(.secondary)
                        }.padding(20)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(filteredItems) { item in
                            Button { selected = item } label: { tile(item) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview \(item.title), \(CompanionItemCatalog.registeredDesign(for: item).label)")
                                .accessibilityIdentifier("marketplace.design.\(item.id.prefix(12))")
                        }
                    }
                    if let selected { detail(selected) }
                }
                Text(store.marketplaceMessage)
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("marketplace.status")
                rules
            }.padding(24).frame(maxWidth: 980, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onChange(of: page) { _, newPage in
            if newPage == .collection { selected = store.itemLibrary.first }
            if newPage == .discover { selected = CompanionItemCatalog.designs.first }
        }
        .onChange(of: store.itemLibrary) { _, items in
            if page == .collection, let selected, !items.contains(selected) { self.selected = items.first }
        }
        .sheet(item: $store.importedMarketItem, onDismiss: completeImportHandoff) { item in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Review imported recipe").font(.title2)
                    Text("Creator and license are declarations in the file. Registration is checked against this app’s local Alpha registry.")
                        .foregroundStyle(.secondary)
                    detail(item, allowsRemoval: false)
                    Text(store.marketplaceMessage).font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("marketplace.import.status")
                    Button("Done") { store.importedMarketItem = nil }.keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("marketplace.import.done")
                }.padding(24)
            }.frame(width: 560, height: 570)
        }
        .confirmationDialog("Remove this local design?", isPresented: Binding(
            get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
            if let removal {
                Button("Remove \(removal.title)", role: .destructive) {
                    if store.removeMarketItem(removal), selected?.id == removal.id { selected = nil }
                    self.removal = nil
                }
            }
            Button("Cancel", role: .cancel) { removal = nil }
        } message: {
            Text("Also removes this item from your current and saved outfit. Shared recipe files stay where you exported them.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MARKETPLACE · LOCAL ALPHA").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(ArchiPalette.violet)
            Text("Small things. Your kind of magic.").font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("Discover something useful, make it your own, and wear it with ARCHi.").foregroundStyle(.secondary)
            Text("\(store.itemLibrary.count) of 8 local designs · No checkout or wallet")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filteredItems: [CompanionItemPackage] {
        let items = page == .collection ? store.itemLibrary : CompanionItemCatalog.designs
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? items : items.filter { ($0.title + " " + $0.creator).localizedCaseInsensitiveContains(needle) }
    }

    private var outfit: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Wearing now: \(store.preferences.equipment.item?.title ?? "No item")")
                .font(.callout.weight(.medium)).accessibilityIdentifier("marketplace.outfit.current")
            Text(nextVisitOutfit).accessibilityIdentifier("marketplace.outfit.saved")
            if store.marketplaceOutfitReadable, store.preferences.equipment != store.savedMarketplaceEquipment {
                Text("Equipping changes this visit. Save your choices in What I remember to keep them for next time.")
            }
            Button("Review saved choices") { store.open(.memory) }
                .accessibilityIdentifier("marketplace.outfit.review")
        }.font(.caption).foregroundStyle(.secondary)
    }

    private var nextVisitOutfit: String {
        guard store.marketplaceOutfitReadable else { return "Next visit: saved outfit unavailable. Review profile recovery in What I remember." }
        guard let saved = store.savedMarketplaceEquipment else { return "Next visit: no saved outfit" }
        return "Next visit: \(saved.item?.title ?? "No item") · saved"
    }

    private func tile(_ item: CompanionItemPackage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            CompanionEquipmentArt(equipment: .init(hand: .focusStaff, design: item), size: 88, activated: false, reduceMotion: true)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            Text(item.title).font(.headline).lineLimit(2)
            Text(item.creator).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(item.action == .decoration ? "Wearable" : "Point to a passage").font(.caption)
            Text(store.itemLibrary.contains(item) ? "In My items" : "Included recipe").font(.caption).foregroundStyle(ArchiPalette.violet)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected?.id == item.id ? ArchiPalette.violet : Color.secondary.opacity(0.18), lineWidth: selected?.id == item.id ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func detail(_ item: CompanionItemPackage, allowsRemoval: Bool = true) -> some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    CompanionEquipmentArt(equipment: .init(hand: .focusStaff, design: item), size: 96, activated: false, reduceMotion: true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.title3.weight(.semibold))
                        Text("\(item.creator) · Design revision \(item.revision)").font(.caption).foregroundStyle(.secondary)
                        Text(CompanionItemCatalog.registeredDesign(for: item).label).font(.caption.weight(.semibold)).foregroundStyle(ArchiPalette.violet)
                        Text(item.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Text(item.action == .pointSelection
                     ? "Local utility: point to a passage you select in Work together. \(item.defaultGesture.summary) Your kept gesture takes precedence."
                     : "Decorative wearable. It cannot point, read a document or run a command.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Recipe license: \(item.license.rawValue) · Canonical Arena effects: none")
                    .font(.caption).foregroundStyle(.secondary)
                if collectionIsFull(for: item) {
                    Text("Your collection is full. Remove a design in My items before adding this one. You can still edit or export this recipe.")
                        .font(.callout).foregroundStyle(.secondary)
                        .accessibilityIdentifier("marketplace.collection-full")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { actions(item, allowsRemoval: allowsRemoval) }
                    VStack(alignment: .leading) { actions(item, allowsRemoval: allowsRemoval) }
                }
                if store.canUseMarketItemInWorkTogether(item) {
                    Button("Use in Work together", systemImage: "text.cursor") { handoff(.workTogether(item)) }
                        .accessibilityHint("Opens your working copy. Select a passage there to point to it.")
                        .accessibilityIdentifier("marketplace.use-work-together")
                }
                Text("Design fingerprint · \(item.id)")
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private func actions(_ item: CompanionItemPackage, allowsRemoval: Bool) -> some View {
        if store.itemLibrary.contains(item) {
            Button(store.preferences.equipment.design?.id == item.id ? "Equipped · Unequip" : "Equip") {
                if store.preferences.equipment.design?.id == item.id { _ = store.unequipMarketItem(item) }
                else { _ = store.equipMarketItem(item) }
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("marketplace.equip")
            if allowsRemoval { Button("Remove", role: .destructive) { removal = item } }
        } else {
            Button("Add to My items", systemImage: "plus") { _ = store.collectMarketItem(item) }
                .buttonStyle(.borderedProminent).disabled(!item.isValid || collectionIsFull(for: item))
                .accessibilityIdentifier("marketplace.collect")
        }
        Button("Export recipe") { store.exportMarketItem(item) }.disabled(!item.isValid)
        Button("Make a variation") { handoff(.variation(item)) }
            .accessibilityIdentifier("marketplace.variation")
    }

    private func collectionIsFull(for item: CompanionItemPackage) -> Bool {
        !store.itemLibrary.contains(item) && store.itemLibrary.count >= CompanionItemPackage.maximumLibraryCount
    }

    /// Finish dismissing review before revealing the destination. In particular,
    /// changing the draft must not leave Create hidden behind the import sheet.
    private func handoff(_ action: ImportHandoff) {
        if store.importedMarketItem != nil {
            importHandoff = action
            store.importedMarketItem = nil
        } else { perform(action) }
    }

    private func completeImportHandoff() {
        guard let action = importHandoff else { return }
        importHandoff = nil
        perform(action)
    }

    private func perform(_ action: ImportHandoff) {
        switch action {
        case .variation(let item):
            draft = item
            draft.creator = "Local creator"
            page = .create
        case .workTogether(let item):
            _ = store.useMarketItemInWorkTogether(item)
        }
    }

    private var creator: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make your Focus Staff").font(.title3.weight(.semibold))
            Text("Choose a bounded local design. Changing any registered recipe creates an unregistered variation. It adds no canon game power.")
                .foregroundStyle(.secondary).font(.callout)
            VStack(alignment: .leading, spacing: 12) {
                TextField("Item name (24 characters)", text: $draft.title).accessibilityIdentifier("marketplace.create.title")
                TextField("Creator (48 characters)", text: $draft.creator)
                TextField("Description (160 characters)", text: $draft.summary, axis: .vertical).lineLimit(2...3)
                Picker("Color", selection: $draft.palette) { ForEach(CompanionItemPackage.Palette.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Crown", selection: $draft.crown) { ForEach(CompanionItemPackage.Crown.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                Picker("Local action", selection: $draft.action) {
                    Text("Wear only").tag(CompanionItemPackage.Action.decoration)
                    Text("Point to selected passage").tag(CompanionItemPackage.Action.pointSelection)
                }
                if draft.action == .pointSelection {
                    Picker("Pace", selection: $draft.defaultGesture.pace) { ForEach(FocusGestureConfiguration.Pace.allCases) { Text($0.title).tag($0) } }
                    Picker("Sparkle", selection: $draft.defaultGesture.sparkle) { ForEach(FocusGestureConfiguration.Sparkle.allCases) { Text($0.title).tag($0) } }
                    Picker("Hold", selection: $draft.defaultGesture.hold) { ForEach(FocusGestureConfiguration.Hold.allCases) { Text($0.title).tag($0) } }
                }
                Picker("Recipe license", selection: $draft.license) { ForEach(CompanionItemPackage.License.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("Design revision \(draft.revision)", value: $draft.revision, in: 1...999)
            }.textFieldStyle(.roundedBorder)
            if draft.isValid { detail(draft) }
            else { Text("Enter a name and creator within the displayed limits. Shorten the description if needed. Line breaks and control characters are not accepted.").foregroundStyle(.red).font(.callout) }
            Text("Share only a recipe you have rights to distribute under your chosen license. Creator names are self-declared; they do not confer a Hampton seal.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("One companion. Clear item rules.").font(.headline)
            Text("Registered means an exact design matches the approved local Alpha catalog and its ruleset. Unregistered recipes are for local looks and explicitly chosen desktop utilities; they cannot affect canon battle stats, rewards or progression. No Arena effects are approved in this release.")
            Text("A design fingerprint identifies content. It is not proof of ownership, scarcity or NFT issuance. Future editions and Arena eligibility require separate verification.")
            HStack {
                Button("Review saved choices") { store.open(.memory) }
                Link("Open-source foundation", destination: URL(string: "https://github.com/cr8ph8/ARCHi")!)
            }
        }.font(.callout).foregroundStyle(.secondary)
    }
}
