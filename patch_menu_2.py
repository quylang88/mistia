with open('./Mistia/Features/Transactions/TransactionsView.swift', 'r') as f:
    content = f.read()

search = """    private var filterChipsHStack: some View {
        HStack(spacing: 8) {
            if activeFilterCount > 0 {
                filterMenu(isActive: true) {"""

replace = """    private var filterChipsHStack: some View {
        HStack(spacing: 8) {
            if activeFilterCount > 0 {
                filterMenu(isActive: true) {"""

content = content.replace(search, replace)

with open('./Mistia/Features/Transactions/TransactionsView.swift', 'w') as f:
    f.write(content)
