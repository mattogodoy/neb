import SwiftUI
import NebCore

struct FindBarView: View {
    @Bindable var viewModel: TimelineViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField("Search messages", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { viewModel.nextSearchResult() }
                .onChange(of: viewModel.searchQuery) {
                    viewModel.performSearch()
                }

            if !viewModel.searchQuery.isEmpty {
                matchCountLabel
            }

            Button(action: { viewModel.previousSearchResult() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchResultIDs.isEmpty)

            Button(action: { viewModel.nextSearchResult() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.searchResultIDs.isEmpty)

            Button(action: { viewModel.clearSearch() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { isFocused = true }
    }

    @ViewBuilder
    private var matchCountLabel: some View {
        if viewModel.searchResultIDs.isEmpty {
            Text("No results")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Text("\(viewModel.currentSearchIndex + 1) of \(viewModel.searchResultIDs.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
