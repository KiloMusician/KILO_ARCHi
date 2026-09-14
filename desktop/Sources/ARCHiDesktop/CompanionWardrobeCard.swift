import SwiftUI

@MainActor
struct CompanionWardrobeCard: View {
    @ObservedObject var store: CompanionStore
    private var item: CompanionItemDescriptor { store.preferences.equipment.item ?? CompanionItemID.focusStaff.item }
    private var previewEquipment: CompanionEquipment { store.preferences.equipment.isEmpty ? .init(hand: .focusStaff) : store.preferences.equipment }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wardrobe").font(.system(size: 17, weight: .medium, design: .rounded))
                Text("Wear something useful. Stay yourself.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 18) {
                    if store.hasPersonalQiMon {
                        CompanionEquipmentArt(equipment: previewEquipment, size: 92,
                            activated: false, reduceMotion: true)
                    } else {
                    CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                        size: 92, reduceMotion: true, treatment: store.preferences.visualTreatment,
                        recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                        equipment: previewEquipment)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Text("\(item.creator) · \(item.provenanceLabel)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(item.effectDescription)
                            .font(.system(size: 12)).lineSpacing(3)
                        Text("Included local item · No purchase needed")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(store.preferences.equipment.isEmpty ? "Equip" : "Unequip") {
                        store.preferences.equipment = store.preferences.equipment.isEmpty
                            ? CompanionEquipment(hand: .focusStaff) : .empty
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(store.preferences.equipment.isEmpty ? "Equip Focus Staff" : "Unequip current item")
                    .accessibilityIdentifier("wardrobe.focus-staff.equip")
                }
                Divider()
                Text("Select a passage in Work together, then choose Point with staff. You can preview a nearby position before moving ARCHi.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                Button("Browse Marketplace", systemImage: "bag") { store.open(.marketplace) }
                    .buttonStyle(.borderless)
                Button("Open Work together") { store.open(.context) }
                    .buttonStyle(.borderless)
                Text("Save choices in What I remember to keep your outfit for the next visit. Explore the Marketplace to create and collect local designs.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Divider()
                FocusGestureTeachingCard(store: store)
            }
        }
    }
}
