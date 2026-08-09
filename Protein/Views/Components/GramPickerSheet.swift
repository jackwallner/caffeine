import SwiftUI

/// Free-form gram entry, for the meals the presets don't cover.
///
/// A wheel gives exact one-gram entry without bringing up a keyboard.
struct GramPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Double) -> Void

    @State private var grams: Int = 25

    private let choices: [Int] = Array(1...200)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Grams", selection: $grams) {
                    ForEach(choices, id: \.self) { value in
                        Text("\(value) g")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 200)

                Button {
                    onAdd(Double(grams))
                    dismiss()
                } label: {
                    Text("Add \(grams) g")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.proteinGradient, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .navigationTitle("Add protein")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }
}
