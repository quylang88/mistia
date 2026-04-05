import re

with open("Mistia/Features/Transactions/TransactionEditorSheet.swift", "r") as f:
    text = f.read()

# Fix the quotes inside the MistiaArchiveSection popupMessage
text = text.replace('"Mục đã lưu trữ"', '\\"Mục đã lưu trữ\\"')
text = text.replace('"Archived items"', '\\"Archived items\\"')

with open("Mistia/Features/Transactions/TransactionEditorSheet.swift", "w") as f:
    f.write(text)
