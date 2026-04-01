with open('./Mistia/Features/Transactions/TransactionsView.swift', 'r') as f:
    content = f.read()

search = """        let menu = Menu {
            content()
        } label: {
            label()
        }
        .menuIndicator(.hidden)"""

replace = """        let menu = Menu {
            content()
        } label: {
            label()
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)"""

content = content.replace(search, replace)

with open('./Mistia/Features/Transactions/TransactionsView.swift', 'w') as f:
    f.write(content)
