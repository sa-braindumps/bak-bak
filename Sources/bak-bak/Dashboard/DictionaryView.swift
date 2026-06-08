import SwiftUI

struct DictionaryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var newHeard = ""
    @State private var newIntended = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dictionary")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(viewModel.vocab.count) entries")
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            HStack {
                TextField("What Whisper hears", text: $newHeard)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                TextField("What you mean", text: $newIntended)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    guard !newHeard.isEmpty, !newIntended.isEmpty else { return }
                    viewModel.addVocabEntry(heard: newHeard, intended: newIntended)
                    newHeard = ""
                    newIntended = ""
                }
                .disabled(newHeard.isEmpty || newIntended.isEmpty)
            }
            .padding()

            Divider()

            if viewModel.vocab.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "book")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No vocabulary entries yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Add corrections above, or say \"no, X is Y\" while dictating.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.vocab.sorted(by: { $0.key < $1.key }), id: \.key) { heard, intended in
                        HStack {
                            Text(heard)
                                .fontWeight(.medium)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(intended)
                            Spacer()
                            Button(action: { viewModel.removeVocabEntry(heard: heard) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
