import SwiftUI

struct SortMenu: View {
    @Binding var sortField: SortField
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            Picker("Sort by", selection: $sortField) {
                ForEach(SortField.allCases) { field in
                    Text(field.displayLabel).tag(field)
                }
            }
            Divider()
            Picker("Order", selection: $ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}
