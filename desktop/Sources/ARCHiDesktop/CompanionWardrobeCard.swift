import SwiftUI

@MainActor
struct CompanionWardrobeCard: View {
    @ObservedObject var store: CompanionStore
    private let item = CompanionItemID.focusStaff.item

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wardrobe").font(.system(size: 17, weight: .medium, design: .rounded))
                Text("Wear something useful. Stay yourself.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(alignment: .center, spacing: 18) {
                    if store.hasPersonalQiMon {
                        CompanionEquipmentArt(equipment: CompanionEquipment(hand: .focusStaff), size: 92,
                            activated: false, reduceMotion: true)
                    } else {
                    CompanionPresenceArt(form: store.presentationForm, family: store.presentationFamily,
                        size: 92, reduceMotion: true, treatment: store.preferences.visualTreatment,
                        recipe: store.presentationRecipe, naturalVariation: store.presentationNaturalVariation,
                        equipment: CompanionEquipment(hand: .focusStaff))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        Text("\(item.creator) · \(item.provenanceLabel)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("Point to a selected passage with a gesture you can shape.")
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
                    .accessibilityLabel(store.preferences.equipment.isEmpty ? "Equip Focus Staff" : "Unequip Focus Staff")
                    .accessibilityIdentifier("wardrobe.focus-staff.equip")
                }
                Divider()
                Text("Select a passage in Work together, then choose Point with staff. You can preview a nearby position before moving ARCHi.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                Button("Open Work together") { store.open(.context) }
                    .buttonStyle(.borderless)
                Text("Save choices in What I remember to keep your outfit for the next visit. Creator shops and collectible editions are coming later.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Divider()
                FocusGestureTeachingCard(store: store)
            }
        }
    }
}
