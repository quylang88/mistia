import re

with open("Mistia/Features/Transactions/TransactionEditorSheet.swift", "r") as f:
    content = f.read()

# Replace ScrollView + VStack with Form
content = re.sub(
    r'ScrollView\(showsIndicators: false\) \{\s*VStack\(spacing: 16\) \{',
    r'Form {',
    content
)

content = re.sub(
    r'\}\s*\.padding\(\.horizontal, 18\)\s*\.padding\(\.top, 10\)\s*\.padding\(\.bottom, 32\)\s*\}',
    r'}',
    content
)

# Replace ZStack { MistiaBackgroundView ... } with just standard background logic
content = re.sub(
    r'ZStack \{\s*MistiaBackgroundView\(tone: \.standard\)\s*Form \{',
    r'Form {',
    content
)
# We also have a trailing bracket for the ZStack
content = re.sub(
    r'\}\s*\.navigationTitle\(navigationTitle\)',
    r'.navigationTitle(navigationTitle)',
    content
)

with open("Mistia/Features/Transactions/TransactionEditorSheet.swift", "w") as f:
    f.write(content)
