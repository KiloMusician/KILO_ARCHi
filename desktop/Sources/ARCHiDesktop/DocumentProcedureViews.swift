import SwiftUI

/// Procedure text is deliberately authored and reviewed here, never silently
/// extracted from a model reply or the shared document.
@MainActor
struct KeepDocumentProcedureView: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord
    @State private var title = ""
    @State private var instruction = ""

    var body: some View {
        if record.state == .applied, record.feedback?.verdict == .helpful, store.canReviewDocument(record) {
            DisclosureGroup("Keep a procedure from this work") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe the method worth trying again. Keep saves only this name, instruction, requirements and review references on this Mac.")
                        .foregroundStyle(.secondary)
                    TextField("Procedure name", text: $title)
                        .accessibilityIdentifier("document.procedure-name")
                    TextField("Instruction for a later selected passage", text: $instruction, axis: .vertical)
                        .lineLimit(3...8).accessibilityIdentifier("document.procedure-instruction")
                    Text(record.mustBeShorter ? "Requires shorter text" : "No shorter-text requirement")
                    Text(record.preserveNumbersAndLinks ? "Keeps exact numbers and links" : "No exact-token requirement")
                    Text("Review the passage → request this method → check the proposed edit → Apply → review the outcome.")
                        .foregroundStyle(.secondary)
                    Text("This is a candidate method you author. The earlier result supports review; it does not prove the new instruction will work elsewhere.")
                        .foregroundStyle(.secondary)
                    Button("Keep procedure") {
                        if store.keepDocumentProcedure(recordID: record.id, title: title, instruction: instruction) {
                            title = ""; instruction = ""
                        }
                    }
                    .disabled(!store.canKeepDocumentProcedure || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("document.keep-procedure")
                }.padding(.top, 6)
            }.font(.caption2).accessibilityIdentifier("document.procedure-review.\(record.id)")
        }
    }
}

@MainActor
struct DocumentProcedureLibraryView: View {
    @ObservedObject var store: CompanionStore

    var body: some View {
        DisclosureGroup("Saved procedures (\(store.documentProcedures.procedures.count))") {
            VStack(alignment: .leading, spacing: 10) {
                Text("After a helpful applied edit, keep a method in Document work history. Reuse requires a selected passage and matching requirements. Each use remains a fresh proposal.")
                    .foregroundStyle(.secondary)
                if let error = store.documentProcedures.loadError { Text(error).foregroundStyle(.orange) }
                ForEach(store.documentProcedures.procedures) { procedure in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(procedure.title) · v\(procedure.revision)").fontWeight(.medium)
                        Text(procedure.instruction).textSelection(.enabled)
                        Text((procedure.mustBeShorter ? "Shorter text" : "Flexible length") + " · "
                             + (procedure.preserveNumbersAndLinks ? "Exact numbers and links" : "No exact-token requirement"))
                            .foregroundStyle(.secondary)
                        if let reason = store.documentProcedureUnavailable(procedure.binding) {
                            Text(reason).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Use for this passage") { _ = store.prepareDocumentProcedure(procedure.binding) }
                                .disabled(!store.canPrepareDocumentProcedure(procedure))
                                .accessibilityIdentifier("document.use-procedure.\(procedure.id)")
                            Button("Withdraw") { store.withdrawDocumentProcedure(procedure.binding) }
                                .disabled(procedure.withdrawn)
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 5)
                }
            }.padding(.top, 6)
        }.font(.caption).accessibilityIdentifier("document.procedures")
    }
}

@MainActor
struct PreparedDocumentProcedureView: View {
    @ObservedObject var store: CompanionStore
    var body: some View {
        if let use = store.preparedDocumentProcedure {
            VStack(alignment: .leading, spacing: 4) {
                Text("Procedure: \(store.documentProcedures.procedure(matching: use)?.title ?? "Unavailable") · v\(use.revision)")
                    .fontWeight(.medium)
                if let reason = store.documentProcedureUnavailable(use) {
                    Text(reason).foregroundStyle(.orange)
                } else if !store.preparedProcedureMatchesCurrentDraft(question: store.prompt) {
                    Text("The draft, passage or requirements changed. Choose the procedure again, or detach it to send a new instruction.")
                        .foregroundStyle(.orange)
                }
                Button("Detach procedure") { store.clearPreparedDocumentProcedure() }
                    .buttonStyle(.borderless).accessibilityIdentifier("document.detach-procedure")
            }.font(.caption2).accessibilityIdentifier("document.prepared-procedure")
        }
    }
}
