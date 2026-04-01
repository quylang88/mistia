import re

files_to_patch = [
    './Mistia/Features/Management/ManagementEditors.swift',
    './Mistia/Features/Transactions/TransactionEditorSheet.swift'
]

search = """                        ZStack {
                            Circle()
                                .fill(Color(red: 0.65, green: 0.45, blue: 0.98))
                                .frame(width: 30, height: 30)

                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }"""

replace = """                        ZStack {
                            Circle()
                                .fill(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.18))
                                .stroke(Color(red: 0.65, green: 0.45, blue: 0.98).opacity(0.3), lineWidth: 1)
                                .frame(width: 30, height: 30)

                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(red: 0.75, green: 0.55, blue: 1.0))
                        }"""

for file_path in files_to_patch:
    with open(file_path, 'r') as f:
        content = f.read()

    content = content.replace(search, replace)

    with open(file_path, 'w') as f:
        f.write(content)
