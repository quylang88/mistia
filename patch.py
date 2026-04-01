import re

with open('./Mistia/Features/Transactions/TransactionsView.swift', 'r') as f:
    content = f.read()

search = """    private var filterChipsHStack: some View {
        HStack(spacing: 8) {
            if activeFilterCount > 0 {
                Button {
                    withAnimation(.snappy) {
                        selectedSegment = nil
                        filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
                    }
                } label: {
                    TransactionToolbarChip(
                        title: "\\(activeFilterCount)",
                        isActive: true,
                        trailingIcon: "xmark"
                    )
                }
                .buttonBorderShape(.capsule)
                .tint(Color(red: 0.53, green: 0.33, blue: 0.86))
                .buttonStyle(.glassProminent)
                .zIndex(99)
            }"""

replace = """    private var filterChipsHStack: some View {
        HStack(spacing: 8) {
            if activeFilterCount > 0 {
                filterMenu(isActive: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .bold))

                        Text("\\(activeFilterCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.53, green: 0.33, blue: 0.86))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Circle().fill(.white))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                } content: {
                    Text("\\(activeFilterCount) bộ lọc đang áp dụng")

                    Button(role: .destructive) {
                        withAnimation(.snappy) {
                            selectedSegment = nil
                            filterState = TransactionFilterState(timeScope: .allTime, statusScope: .all)
                        }
                    } label: {
                        Text("Xoá tất cả bộ lọc")
                    }
                }
            }"""

content = content.replace(search, replace)

with open('./Mistia/Features/Transactions/TransactionsView.swift', 'w') as f:
    f.write(content)
