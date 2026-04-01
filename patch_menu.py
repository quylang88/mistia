with open('./Mistia/Features/Transactions/TransactionsView.swift', 'r') as f:
    content = f.read()

search = """        let menu = Menu {
            content()
        } label: {
            label()
        }
        .buttonBorderShape(.capsule)"""

replace = """        let menu = Menu {
            content()
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .buttonBorderShape(.capsule)"""

content = content.replace(search, replace)

with open('./Mistia/Features/Transactions/TransactionsView.swift', 'w') as f:
    f.write(content)
